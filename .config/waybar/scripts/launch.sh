#!/bin/bash

killall -9 waybar
killall -9 swaync
killall -9 hypridle

waybar &
swaync &
hypridle &
