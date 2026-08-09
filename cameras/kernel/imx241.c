// SPDX-License-Identifier: GPL-2.0
/*
 * Sony IMX241 camera sensor driver
 *
 * The mode tables and platform details were recovered from Samsung's official
 * Galaxy Book 12 (SM-W720) Windows camera package.  The V4L2/CCI integration
 * follows the interfaces used by the upstream Sony sensor drivers.
 */

#include <linux/acpi.h>
#include <linux/clk.h>
#include <linux/delay.h>
#include <linux/dmi.h>
#include <linux/gpio/consumer.h>
#include <linux/i2c.h>
#include <linux/module.h>
#include <linux/pm_runtime.h>
#include <linux/regulator/consumer.h>

#include <media/v4l2-cci.h>
#include <media/v4l2-ctrls.h>
#include <media/v4l2-device.h>
#include <media/v4l2-fwnode.h>

#define IMX241_REG_MODE_SELECT		CCI_REG8(0x0100)
#define IMX241_MODE_STANDBY		0x00
#define IMX241_MODE_STREAMING		0x01
#define IMX241_REG_SOFTWARE_RESET	CCI_REG8(0x0103)
#define IMX241_REG_CHIP_ID		CCI_REG16(0x0000)
#define IMX241_CHIP_ID			0x0241
#define IMX241_REG_FRAME_LENGTH		CCI_REG16(0x0340)
#define IMX241_REG_EXPOSURE		CCI_REG16(0x0202)
#define IMX241_REG_ANALOG_GAIN		CCI_REG16(0x0204)
#define IMX241_REG_ORIENTATION		CCI_REG8(0x0101)
#define IMX241_REG_TEST_PATTERN		CCI_REG16(0x0600)
#define IMX241_HFLIP			BIT(0)
#define IMX241_VFLIP			BIT(1)

#define IMX241_XCLK_FREQ		26000000
#define IMX241_LINK_FREQ		360966667LL
#define IMX241_PIXEL_RATE		144386667LL
#define IMX241_NUM_DATA_LANES		2
#define IMX241_VTS_MAX			0xffff
#define IMX241_EXPOSURE_MIN		4
#define IMX241_EXPOSURE_MARGIN		5
#define IMX241_GAIN_MAX			0x00f0

#define IMX241_NATIVE_WIDTH		2592U
#define IMX241_NATIVE_HEIGHT		1944U

static const char * const imx241_supply_names[] = {
	"vana",
	"vdig",
	"vif",
};

#define IMX241_NUM_SUPPLIES ARRAY_SIZE(imx241_supply_names)

#include "imx241-regs.h"

struct imx241_mode {
	u32 width;
	u32 height;
	u32 vts;
	u32 pixels_per_line;
	const struct cci_reg_sequence *regs;
	u32 num_regs;
};

/* Register 0x0342 uses half-pixel units in the Samsung tables. */
static const struct imx241_mode imx241_modes[] = {
	{
		.width = 2592,
		.height = 1944,
		.vts = 2281,
		.pixels_per_line = 2912,
		.regs = imx241_full_regs,
		.num_regs = ARRAY_SIZE(imx241_full_regs),
	},
	{
		.width = 1296,
		.height = 972,
		.vts = 2076,
		.pixels_per_line = 3200,
		.regs = imx241_binned_regs,
		.num_regs = ARRAY_SIZE(imx241_binned_regs),
	},
};

static const s64 imx241_link_freq_menu[] = {
	IMX241_LINK_FREQ,
};

static const char * const imx241_test_pattern_menu[] = {
	"Disabled",
	"Solid Colour",
	"Eight Vertical Colour Bars",
	"Colour Bars With Fade to Grey",
	"Pseudorandom Sequence (PN9)",
};

static const u32 imx241_codes[] = {
	MEDIA_BUS_FMT_SRGGB10_1X10,
	MEDIA_BUS_FMT_SGRBG10_1X10,
	MEDIA_BUS_FMT_SGBRG10_1X10,
	MEDIA_BUS_FMT_SBGGR10_1X10,
};

struct imx241 {
	struct device *dev;
	struct regmap *regmap;
	struct clk *clk;
	struct regulator_bulk_data supplies[IMX241_NUM_SUPPLIES];
	struct gpio_desc *reset_gpio;
	bool galaxy_book_12;

	struct v4l2_subdev sd;
	struct media_pad pad;
	struct v4l2_ctrl_handler ctrl_handler;
	struct v4l2_ctrl *link_freq;
	struct v4l2_ctrl *pixel_rate;
	struct v4l2_ctrl *hblank;
	struct v4l2_ctrl *vblank;
	struct v4l2_ctrl *exposure;
	struct v4l2_ctrl *hflip;
	struct v4l2_ctrl *vflip;
	const struct imx241_mode *cur_mode;
	/* Protect mode selection, controls and streaming state. */
	struct mutex mutex;
};

static inline struct imx241 *to_imx241(struct v4l2_subdev *sd)
{
	return container_of(sd, struct imx241, sd);
}

static u32 imx241_get_format_code(struct imx241 *imx241)
{
	unsigned int index = (imx241->vflip->val ? 2 : 0) |
			     (imx241->hflip->val ? 1 : 0);

	return imx241_codes[index];
}

static void imx241_update_exposure_range(struct imx241 *imx241)
{
	s64 maximum = imx241->cur_mode->height + imx241->vblank->val -
		      IMX241_EXPOSURE_MARGIN;
	s64 value = min_t(s64, maximum, imx241->exposure->val);

	__v4l2_ctrl_modify_range(imx241->exposure, IMX241_EXPOSURE_MIN,
				 maximum, 1, value);
}

static int imx241_set_ctrl(struct v4l2_ctrl *ctrl)
{
	struct imx241 *imx241 =
		container_of(ctrl->handler, struct imx241, ctrl_handler);
	int ret = 0;

	if (ctrl->id == V4L2_CID_VBLANK)
		imx241_update_exposure_range(imx241);

	if (!pm_runtime_get_if_in_use(imx241->dev))
		return 0;

	switch (ctrl->id) {
	case V4L2_CID_VBLANK:
		ret = cci_write(imx241->regmap, IMX241_REG_FRAME_LENGTH,
				imx241->cur_mode->height + ctrl->val, NULL);
		break;
	case V4L2_CID_EXPOSURE:
		ret = cci_write(imx241->regmap, IMX241_REG_EXPOSURE,
				ctrl->val, NULL);
		break;
	case V4L2_CID_ANALOGUE_GAIN:
		ret = cci_write(imx241->regmap, IMX241_REG_ANALOG_GAIN,
				ctrl->val, NULL);
		break;
	case V4L2_CID_TEST_PATTERN:
		ret = cci_write(imx241->regmap, IMX241_REG_TEST_PATTERN,
				ctrl->val, NULL);
		break;
	case V4L2_CID_HFLIP:
	case V4L2_CID_VFLIP:
		ret = cci_write(imx241->regmap, IMX241_REG_ORIENTATION,
				(imx241->hflip->val ? IMX241_HFLIP : 0) |
				(imx241->vflip->val ? IMX241_VFLIP : 0), NULL);
		break;
	default:
		ret = -EINVAL;
	}

	pm_runtime_put(imx241->dev);
	return ret;
}

static const struct v4l2_ctrl_ops imx241_ctrl_ops = {
	.s_ctrl = imx241_set_ctrl,
};

static void imx241_fill_format(struct imx241 *imx241,
			       const struct imx241_mode *mode,
			       struct v4l2_mbus_framefmt *format)
{
	format->width = mode->width;
	format->height = mode->height;
	format->code = imx241_get_format_code(imx241);
	format->field = V4L2_FIELD_NONE;
}

static int imx241_enum_mbus_code(struct v4l2_subdev *sd,
				 struct v4l2_subdev_state *state,
				 struct v4l2_subdev_mbus_code_enum *code)
{
	struct imx241 *imx241 = to_imx241(sd);

	if (code->index)
		return -EINVAL;

	mutex_lock(&imx241->mutex);
	code->code = imx241_get_format_code(imx241);
	mutex_unlock(&imx241->mutex);
	return 0;
}

static int imx241_enum_frame_size(struct v4l2_subdev *sd,
				  struct v4l2_subdev_state *state,
				  struct v4l2_subdev_frame_size_enum *fse)
{
	struct imx241 *imx241 = to_imx241(sd);
	u32 code;

	if (fse->index >= ARRAY_SIZE(imx241_modes))
		return -EINVAL;

	mutex_lock(&imx241->mutex);
	code = imx241_get_format_code(imx241);
	mutex_unlock(&imx241->mutex);
	if (fse->code != code)
		return -EINVAL;

	fse->min_width = imx241_modes[fse->index].width;
	fse->max_width = imx241_modes[fse->index].width;
	fse->min_height = imx241_modes[fse->index].height;
	fse->max_height = imx241_modes[fse->index].height;
	return 0;
}

static int imx241_get_format(struct v4l2_subdev *sd,
			     struct v4l2_subdev_state *state,
			     struct v4l2_subdev_format *fmt)
{
	struct imx241 *imx241 = to_imx241(sd);

	mutex_lock(&imx241->mutex);
	if (fmt->which == V4L2_SUBDEV_FORMAT_TRY)
		fmt->format = *v4l2_subdev_state_get_format(state, fmt->pad);
	else
		imx241_fill_format(imx241, imx241->cur_mode, &fmt->format);
	mutex_unlock(&imx241->mutex);

	return 0;
}

static int imx241_set_format(struct v4l2_subdev *sd,
			     struct v4l2_subdev_state *state,
			     struct v4l2_subdev_format *fmt)
{
	struct imx241 *imx241 = to_imx241(sd);
	const struct imx241_mode *mode;
	s64 hblank, vblank;

	mutex_lock(&imx241->mutex);
	mode = v4l2_find_nearest_size(imx241_modes, ARRAY_SIZE(imx241_modes),
				      width, height, fmt->format.width,
				      fmt->format.height);
	imx241_fill_format(imx241, mode, &fmt->format);

	if (fmt->which == V4L2_SUBDEV_FORMAT_TRY) {
		*v4l2_subdev_state_get_format(state, fmt->pad) = fmt->format;
	} else {
		imx241->cur_mode = mode;
		hblank = mode->pixels_per_line - mode->width;
		vblank = mode->vts - mode->height;
		__v4l2_ctrl_modify_range(imx241->hblank, hblank, hblank, 1,
					 hblank);
		__v4l2_ctrl_modify_range(imx241->vblank, vblank,
					 IMX241_VTS_MAX - mode->height, 1,
					 vblank);
		__v4l2_ctrl_s_ctrl(imx241->vblank, vblank);
	}
	mutex_unlock(&imx241->mutex);

	return 0;
}

static int imx241_get_selection(struct v4l2_subdev *sd,
				struct v4l2_subdev_state *state,
				struct v4l2_subdev_selection *sel)
{
	struct imx241 *imx241 = to_imx241(sd);

	if (sel->target == V4L2_SEL_TGT_NATIVE_SIZE ||
	    sel->target == V4L2_SEL_TGT_CROP_BOUNDS ||
	    sel->target == V4L2_SEL_TGT_CROP_DEFAULT) {
		sel->r.left = 0;
		sel->r.top = 0;
		sel->r.width = IMX241_NATIVE_WIDTH;
		sel->r.height = IMX241_NATIVE_HEIGHT;
		return 0;
	}

	if (sel->target != V4L2_SEL_TGT_CROP)
		return -EINVAL;

	mutex_lock(&imx241->mutex);
	if (sel->which == V4L2_SUBDEV_FORMAT_TRY) {
		sel->r = *v4l2_subdev_state_get_crop(state, sel->pad);
	} else {
		sel->r.left = 0;
		sel->r.top = 0;
		sel->r.width = IMX241_NATIVE_WIDTH;
		sel->r.height = IMX241_NATIVE_HEIGHT;
	}
	mutex_unlock(&imx241->mutex);
	return 0;
}

static int imx241_open(struct v4l2_subdev *sd, struct v4l2_subdev_fh *fh)
{
	struct imx241 *imx241 = to_imx241(sd);
	struct v4l2_mbus_framefmt *format;
	struct v4l2_rect *crop;

	mutex_lock(&imx241->mutex);
	format = v4l2_subdev_state_get_format(fh->state, 0);
	imx241_fill_format(imx241, &imx241_modes[0], format);
	crop = v4l2_subdev_state_get_crop(fh->state, 0);
	crop->left = 0;
	crop->top = 0;
	crop->width = IMX241_NATIVE_WIDTH;
	crop->height = IMX241_NATIVE_HEIGHT;
	mutex_unlock(&imx241->mutex);
	return 0;
}

static int imx241_start_streaming(struct imx241 *imx241)
{
	int ret;

	ret = cci_multi_reg_write(imx241->regmap, imx241->cur_mode->regs,
				  imx241->cur_mode->num_regs, NULL);
	if (ret)
		return dev_err_probe(imx241->dev, ret,
				     "failed to program sensor mode\n");

	ret = __v4l2_ctrl_handler_setup(&imx241->ctrl_handler);
	if (ret)
		return ret;

	return cci_write(imx241->regmap, IMX241_REG_MODE_SELECT,
			 IMX241_MODE_STREAMING, NULL);
}

static int imx241_set_stream(struct v4l2_subdev *sd, int enable)
{
	struct imx241 *imx241 = to_imx241(sd);
	int ret = 0;

	mutex_lock(&imx241->mutex);
	if (enable) {
		ret = pm_runtime_resume_and_get(imx241->dev);
		if (ret < 0)
			goto out;
		ret = imx241_start_streaming(imx241);
		if (ret)
			pm_runtime_put(imx241->dev);
	} else {
		cci_write(imx241->regmap, IMX241_REG_MODE_SELECT,
			  IMX241_MODE_STANDBY, NULL);
		pm_runtime_put(imx241->dev);
	}
out:
	mutex_unlock(&imx241->mutex);
	return ret;
}

static const struct v4l2_subdev_video_ops imx241_video_ops = {
	.s_stream = imx241_set_stream,
};

static const struct v4l2_subdev_pad_ops imx241_pad_ops = {
	.enum_mbus_code = imx241_enum_mbus_code,
	.enum_frame_size = imx241_enum_frame_size,
	.get_fmt = imx241_get_format,
	.set_fmt = imx241_set_format,
	.get_selection = imx241_get_selection,
};

static const struct v4l2_subdev_ops imx241_subdev_ops = {
	.video = &imx241_video_ops,
	.pad = &imx241_pad_ops,
};

static const struct v4l2_subdev_internal_ops imx241_internal_ops = {
	.open = imx241_open,
};

static const guid_t galaxy_book_12_camera_on_guid =
	GUID_INIT(0x952db6f5, 0xb3da, 0x473c,
		  0x9a, 0x1b, 0x1d, 0xdb, 0xb2, 0x7d, 0xa9, 0xb4);
static const guid_t galaxy_book_12_camera_off_guid =
	GUID_INIT(0x239aba6f, 0x46f9, 0x4884,
		  0xb6, 0x7c, 0x0b, 0x1d, 0x84, 0xdc, 0x58, 0x5c);

static bool imx241_is_galaxy_book_12(struct device *dev)
{
	struct acpi_device *adev = ACPI_COMPANION(dev);

	return adev && acpi_dev_hid_uid_match(adev, "INT347F", NULL) &&
		dmi_match(DMI_SYS_VENDOR, "SAMSUNG ELECTRONICS CO., LTD.") &&
		dmi_match(DMI_PRODUCT_NAME, "Galaxy Book 12");
}

static int imx241_galaxy_book_12_set_power(struct device *dev, bool on)
{
	const guid_t *guid = on ? &galaxy_book_12_camera_on_guid :
				  &galaxy_book_12_camera_off_guid;
	union acpi_object *object;
	acpi_handle handle;
	acpi_status status;

	status = acpi_get_handle(NULL, "\\_SB.PCI0.DSC1", &handle);
	if (ACPI_FAILURE(status))
		return dev_err_probe(dev, -ENODEV,
				     "cannot find Samsung front-camera control logic\n");

	object = acpi_evaluate_dsm(handle, guid, 0, 0, NULL);
	if (!object)
		return dev_err_probe(dev, -EIO,
				     "Samsung front-camera power _DSM failed\n");
	ACPI_FREE(object);
	return 0;
}

static int imx241_power_on(struct device *dev)
{
	struct imx241 *imx241 = to_imx241(dev_get_drvdata(dev));
	int ret;

	if (imx241->galaxy_book_12) {
		ret = imx241_galaxy_book_12_set_power(dev, true);
		if (ret)
			return ret;
	}

	ret = regulator_bulk_enable(IMX241_NUM_SUPPLIES, imx241->supplies);
	if (ret)
		goto disable_platform;

	ret = clk_prepare_enable(imx241->clk);
	if (ret)
		goto disable_regulators;

	gpiod_set_value_cansleep(imx241->reset_gpio, 0);
	usleep_range(10000, 12000);
	return 0;

disable_regulators:
	regulator_bulk_disable(IMX241_NUM_SUPPLIES, imx241->supplies);
disable_platform:
	if (imx241->galaxy_book_12)
		imx241_galaxy_book_12_set_power(dev, false);
	return ret;
}

static int imx241_power_off(struct device *dev)
{
	struct imx241 *imx241 = to_imx241(dev_get_drvdata(dev));

	gpiod_set_value_cansleep(imx241->reset_gpio, 1);
	clk_disable_unprepare(imx241->clk);
	regulator_bulk_disable(IMX241_NUM_SUPPLIES, imx241->supplies);
	if (imx241->galaxy_book_12)
		imx241_galaxy_book_12_set_power(dev, false);
	return 0;
}

static int imx241_identify(struct imx241 *imx241)
{
	u64 value = 0;
	unsigned int attempt;
	int ret;

	ret = cci_write(imx241->regmap, IMX241_REG_SOFTWARE_RESET, 1, NULL);
	if (ret)
		return dev_err_probe(imx241->dev, ret,
				     "failed to reset sensor\n");
	fsleep(12000);

	for (attempt = 0; attempt < 20; attempt++) {
		ret = cci_read(imx241->regmap, IMX241_REG_CHIP_ID, &value, NULL);
		if (!ret && value == IMX241_CHIP_ID)
			return 0;
		usleep_range(10000, 12000);
	}
	if (ret)
		return dev_err_probe(imx241->dev, ret,
				     "failed to read chip ID\n");
	if (value != IMX241_CHIP_ID)
		return dev_err_probe(imx241->dev, -ENODEV,
				     "unexpected chip ID 0x%04llx\n", value);
	return 0;
}

static int imx241_init_controls(struct imx241 *imx241)
{
	struct v4l2_fwnode_device_properties props;
	struct v4l2_ctrl_handler *handler = &imx241->ctrl_handler;
	const struct imx241_mode *mode = imx241->cur_mode;
	s64 hblank = mode->pixels_per_line - mode->width;
	s64 vblank = mode->vts - mode->height;
	int ret;

	ret = v4l2_ctrl_handler_init(handler, 10);
	if (ret)
		return ret;

	mutex_init(&imx241->mutex);
	handler->lock = &imx241->mutex;
	imx241->link_freq = v4l2_ctrl_new_int_menu(handler, &imx241_ctrl_ops,
						     V4L2_CID_LINK_FREQ, 0, 0,
						     imx241_link_freq_menu);
	if (imx241->link_freq)
		imx241->link_freq->flags |= V4L2_CTRL_FLAG_READ_ONLY;
	imx241->pixel_rate = v4l2_ctrl_new_std(handler, &imx241_ctrl_ops,
						 V4L2_CID_PIXEL_RATE,
						 IMX241_PIXEL_RATE,
						 IMX241_PIXEL_RATE, 1,
						 IMX241_PIXEL_RATE);
	imx241->hblank = v4l2_ctrl_new_std(handler, &imx241_ctrl_ops,
					      V4L2_CID_HBLANK, hblank,
					      hblank, 1, hblank);
	if (imx241->hblank)
		imx241->hblank->flags |= V4L2_CTRL_FLAG_READ_ONLY;
	imx241->vblank = v4l2_ctrl_new_std(handler, &imx241_ctrl_ops,
					      V4L2_CID_VBLANK, vblank,
					      IMX241_VTS_MAX - mode->height,
					      1, vblank);
	imx241->exposure = v4l2_ctrl_new_std(handler, &imx241_ctrl_ops,
						 V4L2_CID_EXPOSURE,
						 IMX241_EXPOSURE_MIN,
						 mode->vts - IMX241_EXPOSURE_MARGIN,
						 1,
						 mode->vts - IMX241_EXPOSURE_MARGIN);
	v4l2_ctrl_new_std(handler, &imx241_ctrl_ops, V4L2_CID_ANALOGUE_GAIN,
			  0, IMX241_GAIN_MAX, 1, 0);
	v4l2_ctrl_new_std_menu_items(handler, &imx241_ctrl_ops,
				     V4L2_CID_TEST_PATTERN,
				     ARRAY_SIZE(imx241_test_pattern_menu) - 1,
				     0, 0, imx241_test_pattern_menu);
	imx241->hflip = v4l2_ctrl_new_std(handler, &imx241_ctrl_ops,
					      V4L2_CID_HFLIP, 0, 1, 1, 0);
	imx241->vflip = v4l2_ctrl_new_std(handler, &imx241_ctrl_ops,
					      V4L2_CID_VFLIP, 0, 1, 1, 0);
	if (imx241->hflip)
		imx241->hflip->flags |= V4L2_CTRL_FLAG_MODIFY_LAYOUT;
	if (imx241->vflip)
		imx241->vflip->flags |= V4L2_CTRL_FLAG_MODIFY_LAYOUT;

	if (handler->error) {
		ret = handler->error;
		v4l2_ctrl_handler_free(handler);
		mutex_destroy(&imx241->mutex);
		return ret;
	}
	ret = v4l2_fwnode_device_parse(imx241->dev, &props);
	if (ret)
		goto free_handler;
	ret = v4l2_ctrl_new_fwnode_properties(handler, &imx241_ctrl_ops,
					      &props);
	if (ret)
		goto free_handler;

	imx241->sd.ctrl_handler = handler;
	return 0;

free_handler:
	v4l2_ctrl_handler_free(handler);
	mutex_destroy(&imx241->mutex);
	return ret;
}

static int imx241_parse_endpoint(struct imx241 *imx241)
{
	struct v4l2_fwnode_endpoint ep = {
		.bus_type = V4L2_MBUS_CSI2_DPHY,
	};
	struct fwnode_handle *endpoint;
	bool frequency_found = false;
	unsigned int i;
	int ret;

	endpoint = fwnode_graph_get_next_endpoint(dev_fwnode(imx241->dev), NULL);
	if (!endpoint)
		return dev_err_probe(imx241->dev, -EPROBE_DEFER,
				     "waiting for IPU bridge endpoint\n");
	ret = v4l2_fwnode_endpoint_alloc_parse(endpoint, &ep);
	fwnode_handle_put(endpoint);
	if (ret)
		return dev_err_probe(imx241->dev, ret,
				     "failed to parse camera endpoint\n");

	if (ep.bus.mipi_csi2.num_data_lanes != IMX241_NUM_DATA_LANES) {
		ret = dev_err_probe(imx241->dev, -EINVAL,
				    "expected two CSI-2 data lanes, got %u\n",
				    ep.bus.mipi_csi2.num_data_lanes);
		goto out;
	}
	for (i = 0; i < ep.nr_of_link_frequencies; i++)
		if (ep.link_frequencies[i] == IMX241_LINK_FREQ)
			frequency_found = true;
	if (!frequency_found)
		ret = dev_err_probe(imx241->dev, -EINVAL,
				    "required link frequency is missing\n");
out:
	v4l2_fwnode_endpoint_free(&ep);
	return ret;
}

static int imx241_probe(struct i2c_client *client)
{
	struct imx241 *imx241;
	unsigned int i;
	int ret;

	imx241 = devm_kzalloc(&client->dev, sizeof(*imx241), GFP_KERNEL);
	if (!imx241)
		return -ENOMEM;
	imx241->dev = &client->dev;
	imx241->cur_mode = &imx241_modes[0];
	imx241->regmap = devm_cci_regmap_init_i2c(client, 16);
	if (IS_ERR(imx241->regmap))
		return dev_err_probe(imx241->dev, PTR_ERR(imx241->regmap),
				     "failed to initialize CCI\n");

	for (i = 0; i < IMX241_NUM_SUPPLIES; i++)
		imx241->supplies[i].supply = imx241_supply_names[i];
	ret = devm_regulator_bulk_get(imx241->dev, IMX241_NUM_SUPPLIES,
				      imx241->supplies);
	if (ret)
		return dev_err_probe(imx241->dev, ret,
				     "failed to get power rails\n");

	imx241->clk = devm_v4l2_sensor_clk_get_legacy(imx241->dev, NULL,
						      false, 0);
	if (IS_ERR(imx241->clk))
		return dev_err_probe(imx241->dev, PTR_ERR(imx241->clk),
				     "failed to get sensor clock\n");
	if (clk_get_rate(imx241->clk) != IMX241_XCLK_FREQ)
		return dev_err_probe(imx241->dev, -EINVAL,
				     "only a 26 MHz input clock is supported\n");

	imx241->galaxy_book_12 = imx241_is_galaxy_book_12(imx241->dev);
	imx241->reset_gpio = devm_gpiod_get_optional(imx241->dev, "reset",
						     GPIOD_OUT_HIGH);
	if (IS_ERR(imx241->reset_gpio))
		return dev_err_probe(imx241->dev, PTR_ERR(imx241->reset_gpio),
				     "failed to get reset GPIO\n");
	if (imx241->galaxy_book_12 && !imx241->reset_gpio)
		return dev_err_probe(imx241->dev, -ENODEV,
				     "Galaxy Book 12 reset GPIO is missing\n");

	ret = imx241_parse_endpoint(imx241);
	if (ret)
		return ret;

	v4l2_i2c_subdev_init(&imx241->sd, client, &imx241_subdev_ops);
	ret = imx241_power_on(imx241->dev);
	if (ret)
		return ret;
	ret = imx241_identify(imx241);
	if (ret)
		goto power_off;

	ret = imx241_init_controls(imx241);
	if (ret)
		goto power_off;
	imx241->sd.internal_ops = &imx241_internal_ops;
	imx241->sd.flags |= V4L2_SUBDEV_FL_HAS_DEVNODE;
	imx241->sd.entity.function = MEDIA_ENT_F_CAM_SENSOR;
	imx241->pad.flags = MEDIA_PAD_FL_SOURCE;
	ret = media_entity_pads_init(&imx241->sd.entity, 1, &imx241->pad);
	if (ret)
		goto free_controls;

	ret = v4l2_async_register_subdev_sensor(&imx241->sd);
	if (ret)
		goto cleanup_entity;

	pm_runtime_set_active(imx241->dev);
	pm_runtime_enable(imx241->dev);
	pm_runtime_idle(imx241->dev);
	return 0;

cleanup_entity:
	media_entity_cleanup(&imx241->sd.entity);
free_controls:
	v4l2_ctrl_handler_free(&imx241->ctrl_handler);
	mutex_destroy(&imx241->mutex);
power_off:
	imx241_power_off(imx241->dev);
	return ret;
}

static void imx241_remove(struct i2c_client *client)
{
	struct v4l2_subdev *sd = i2c_get_clientdata(client);
	struct imx241 *imx241 = to_imx241(sd);

	v4l2_async_unregister_subdev(sd);
	media_entity_cleanup(&sd->entity);
	v4l2_ctrl_handler_free(&imx241->ctrl_handler);
	mutex_destroy(&imx241->mutex);
	pm_runtime_disable(imx241->dev);
	if (!pm_runtime_status_suspended(imx241->dev))
		imx241_power_off(imx241->dev);
	pm_runtime_set_suspended(imx241->dev);
}

static const struct dev_pm_ops imx241_pm_ops = {
	SET_RUNTIME_PM_OPS(imx241_power_off, imx241_power_on, NULL)
};

static const struct acpi_device_id imx241_acpi_ids[] = {
	{ "INT347F" },
	{ }
};
MODULE_DEVICE_TABLE(acpi, imx241_acpi_ids);

static const struct of_device_id imx241_of_ids[] = {
	{ .compatible = "sony,imx241" },
	{ }
};
MODULE_DEVICE_TABLE(of, imx241_of_ids);

static struct i2c_driver imx241_i2c_driver = {
	.driver = {
		.name = "imx241",
		.pm = &imx241_pm_ops,
		.acpi_match_table = ACPI_PTR(imx241_acpi_ids),
		.of_match_table = imx241_of_ids,
	},
	.probe = imx241_probe,
	.remove = imx241_remove,
};
module_i2c_driver(imx241_i2c_driver);

MODULE_AUTHOR("Galaxy Book 12 Linux contributors");
MODULE_DESCRIPTION("Sony IMX241 camera sensor driver");
MODULE_LICENSE("GPL");
