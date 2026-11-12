cmake_minimum_required(VERSION 3.20)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(hestia)

target_sources(app PRIVATE
  src/main.c
  src/alert.c
  src/battery.c
  src/config.c
  src/config_json.c
  src/link.c
  src/net.c
  src/text.c
  src/ui.c
)
