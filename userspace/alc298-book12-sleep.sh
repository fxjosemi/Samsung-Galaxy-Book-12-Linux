#!/bin/bash
# Reinitialize codec-internal amplifiers after a suspend power cycle.
case "${1:-}" in
    post)
        case "${2:-}" in
            suspend|hibernate|hybrid-sleep|suspend-then-hibernate)
                /usr/local/libexec/alc298-book12-control full --apply || true
                ;;
        esac
        ;;
esac
