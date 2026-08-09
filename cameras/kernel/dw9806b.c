// SPDX-License-Identifier: GPL-2.0
/*
 * Dongwoon DW9806B voice-coil motor driver
 *
 * The register sequence and position encoding used here were recovered from
 * Samsung's official Galaxy Book 12 (SM-W720) Windows camera driver.
 */

#include <linux/delay.h>
#include <linux/i2c.h>
#include <linux/iopoll.h>
#include <linux/module.h>
#include <media/v4l2-async.h>
#include <media/v4l2-ctrls.h>
#include <media/v4l2-device.h>

#define DW9806B_FOCUS_MIN_DAC	0
#define DW9806B_FOCUS_MAX_DAC	1023
#define DW9806B_MAX_FOCUS_POS	(DW9806B_FOCUS_MAX_DAC - \
				 DW9806B_FOCUS_MIN_DAC)
#define DW9806B_FOCUS_STEP	1
#define DW9806B_MOVE_STEP	8
#define DW9806B_MOVE_DELAY_US	1000

#define DW9806B_REG_CONTROL	0x02
#define DW9806B_REG_POSITION_MSB	0x03
#define DW9806B_REG_POSITION_LSB	0x04
#define DW9806B_REG_STATUS	0x05
#define DW9806B_REG_MODE		0x06
#define DW9806B_REG_RESONANCE	0x07

#define DW9806B_STATUS_BUSY	BIT(0)

struct dw9806b_device {
	struct v4l2_ctrl_handler controls;
	struct v4l2_subdev sd;
	u16 physical_position;
	bool position_valid;
};

static inline struct dw9806b_device *to_dw9806b(struct v4l2_subdev *sd)
{
	return container_of(sd, struct dw9806b_device, sd);
}

static int dw9806b_read_status(struct i2c_client *client)
{
	return i2c_smbus_read_byte_data(client, DW9806B_REG_STATUS);
}

static int dw9806b_wait_ready(struct i2c_client *client)
{
	int status, ret;

	ret = read_poll_timeout(dw9806b_read_status, status,
				status < 0 || !(status & DW9806B_STATUS_BUSY),
				DW9806B_MOVE_DELAY_US,
				10 * DW9806B_MOVE_DELAY_US, false, client);
	if (status < 0)
		return status;
	if (ret)
		dev_warn(&client->dev, "actuator remained busy\n");

	return ret;
}

static int dw9806b_set_position(struct i2c_client *client, u16 position)
{
	u8 tx[3];
	int msb, ret;

	ret = dw9806b_wait_ready(client);
	if (ret)
		return ret;

	msb = i2c_smbus_read_byte_data(client, DW9806B_REG_POSITION_MSB);
	if (msb < 0)
		return msb;

	tx[0] = DW9806B_REG_POSITION_MSB;
	tx[1] = (msb & 0xfc) | ((position >> 8) & 0x03);
	tx[2] = position & 0xff;

	ret = i2c_master_send(client, tx, sizeof(tx));
	if (ret < 0)
		return ret;
	if (ret != sizeof(tx))
		return -EIO;

	return 0;
}

static int dw9806b_move_gradually(struct dw9806b_device *dw9806b,
				  struct i2c_client *client, u16 target)
{
	int position = dw9806b->physical_position;
	int step = position <= target ? DW9806B_MOVE_STEP : -DW9806B_MOVE_STEP;
	int ret;

	while (position != target) {
		position += step;
		if ((step > 0 && position > target) ||
		    (step < 0 && position < target))
			position = target;

		ret = dw9806b_set_position(client, position);
		if (ret)
			return ret;
		usleep_range(DW9806B_MOVE_DELAY_US,
			     DW9806B_MOVE_DELAY_US + 100);
	}

	dw9806b->physical_position = target;
	dw9806b->position_valid = true;
	return 0;
}

static int dw9806b_hw_init(struct i2c_client *client)
{
	static const struct {
		u8 reg;
		u8 value;
	} init_sequence[] = {
		{ DW9806B_REG_CONTROL, 0x01 },
		{ DW9806B_REG_CONTROL, 0x00 },
		{ DW9806B_REG_CONTROL, 0x02 },
		{ DW9806B_REG_MODE, 0x61 },
		{ DW9806B_REG_RESONANCE, 0x36 },
	};
	unsigned int i;
	int ret;

	for (i = 0; i < ARRAY_SIZE(init_sequence); i++) {
		ret = i2c_smbus_write_byte_data(client, init_sequence[i].reg,
						init_sequence[i].value);
		if (ret)
			return ret;
		if (i == 1)
			usleep_range(1000, 1100);
	}

	return 0;
}

static int dw9806b_set_ctrl(struct v4l2_ctrl *ctrl)
{
	struct dw9806b_device *dw9806b =
		container_of(ctrl->handler, struct dw9806b_device, controls);
	struct i2c_client *client = v4l2_get_subdevdata(&dw9806b->sd);
	u16 target = DW9806B_FOCUS_MIN_DAC + ctrl->val;
	int control;

	if (ctrl->id != V4L2_CID_FOCUS_ABSOLUTE)
		return -EINVAL;

	/*
	 * The AF rail follows the sensor's streaming power. Register 0x02 loses
	 * its initialized value when that rail turns off, so use it as a cheap
	 * power-cycle detector. Merely opening this subdevice must not runtime-
	 * resume the sensor: PipeWire keeps camera nodes open while idle.
	 */
	control = i2c_smbus_read_byte_data(client, DW9806B_REG_CONTROL);
	if (control < 0) {
		/*
		 * libcamera may apply the default control while enumerating an
		 * otherwise powered-off camera. The V4L2 core retains ctrl->val;
		 * a later AF request while streaming will apply it to hardware.
		 */
		dw9806b->position_valid = false;
		return 0;
	}
	if (control != 0x02 || !dw9806b->position_valid) {
		control = dw9806b_hw_init(client);
		if (control)
			return control;
		control = dw9806b_set_position(client, DW9806B_FOCUS_MIN_DAC);
		if (control)
			return control;
		dw9806b->physical_position = DW9806B_FOCUS_MIN_DAC;
		dw9806b->position_valid = true;
	}

	return dw9806b_move_gradually(dw9806b, client, target);
}

static const struct v4l2_ctrl_ops dw9806b_ctrl_ops = {
	.s_ctrl = dw9806b_set_ctrl,
};

static const struct v4l2_subdev_ops dw9806b_subdev_ops;

static void dw9806b_cleanup(struct dw9806b_device *dw9806b)
{
	v4l2_async_unregister_subdev(&dw9806b->sd);
	v4l2_ctrl_handler_free(&dw9806b->controls);
	media_entity_cleanup(&dw9806b->sd.entity);
}

static int dw9806b_probe(struct i2c_client *client)
{
	struct dw9806b_device *dw9806b;
	struct v4l2_ctrl *focus;
	int ret;

	dw9806b = devm_kzalloc(&client->dev, sizeof(*dw9806b), GFP_KERNEL);
	if (!dw9806b)
		return -ENOMEM;

	v4l2_i2c_subdev_init(&dw9806b->sd, client, &dw9806b_subdev_ops);
	dw9806b->sd.flags |= V4L2_SUBDEV_FL_HAS_DEVNODE;

	v4l2_ctrl_handler_init(&dw9806b->controls, 1);
	focus = v4l2_ctrl_new_std(&dw9806b->controls, &dw9806b_ctrl_ops,
				  V4L2_CID_FOCUS_ABSOLUTE, 0,
				  DW9806B_MAX_FOCUS_POS,
				  DW9806B_FOCUS_STEP, 0);
	if (focus)
		focus->flags |= V4L2_CTRL_FLAG_EXECUTE_ON_WRITE;
	dw9806b->sd.ctrl_handler = &dw9806b->controls;
	if (dw9806b->controls.error) {
		ret = dw9806b->controls.error;
		goto err_controls;
	}

	ret = media_entity_pads_init(&dw9806b->sd.entity, 0, NULL);
	if (ret)
		goto err_controls;
	dw9806b->sd.entity.function = MEDIA_ENT_F_LENS;

	/* The IPU bridge keeps the sensor and its AF rail on during probe. */
	ret = dw9806b_hw_init(client);
	if (ret)
		goto err_entity;
	ret = dw9806b_set_position(client, DW9806B_FOCUS_MIN_DAC);
	if (ret)
		goto err_power_down;
	dw9806b->physical_position = DW9806B_FOCUS_MIN_DAC;
	dw9806b->position_valid = true;

	ret = v4l2_async_register_subdev(&dw9806b->sd);
	if (ret)
		goto err_power_down;

	dev_info(&client->dev, "DW9806B autofocus actuator detected\n");
	return 0;

err_power_down:
	i2c_smbus_write_byte_data(client, DW9806B_REG_CONTROL, 0x01);
err_entity:
	media_entity_cleanup(&dw9806b->sd.entity);
err_controls:
	v4l2_ctrl_handler_free(&dw9806b->controls);
	return dev_err_probe(&client->dev, ret,
			     "failed to initialize DW9806B actuator\n");
}

static void dw9806b_remove(struct i2c_client *client)
{
	struct v4l2_subdev *sd = i2c_get_clientdata(client);
	struct dw9806b_device *dw9806b = to_dw9806b(sd);

	dw9806b_cleanup(dw9806b);
}

static const struct i2c_device_id dw9806b_id_table[] = {
	{ "dw9806b" },
	{ }
};
MODULE_DEVICE_TABLE(i2c, dw9806b_id_table);

static struct i2c_driver dw9806b_i2c_driver = {
	.driver = {
		.name = "dw9806b",
	},
	.probe = dw9806b_probe,
	.remove = dw9806b_remove,
	.id_table = dw9806b_id_table,
};
module_i2c_driver(dw9806b_i2c_driver);

MODULE_AUTHOR("Galaxy Book 12 Linux project");
MODULE_DESCRIPTION("Dongwoon DW9806B autofocus actuator driver");
MODULE_LICENSE("GPL");
