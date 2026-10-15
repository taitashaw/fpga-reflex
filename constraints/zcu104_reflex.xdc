# ZCU104 user LEDs. Pin locations and IO standard from the installed board file
# XilinxBoardStore/boards/Xilinx/zcu104/1.1/part0_pins.xml (GPIO_LED_0_LS .. GPIO_LED_3_LS).
# LED0 servo PWM, LED1 command (stretched), LED2 locked, LED3 guard active.
set_property -dict {PACKAGE_PIN D5 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN D6 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN A5 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN B5 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
# LEDs are viewed by eye; their output delay is not a timing requirement.
set_false_path -to [get_ports {led[*]}]
