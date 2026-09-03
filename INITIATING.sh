#!/system/bin/sh
# Pixel 7 Pro Carrier Patch eUICC Initializer
settings put global apn_override wholesale
am start -a android.settings.EUICC_SETTINGS
