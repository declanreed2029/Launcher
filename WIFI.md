# Launcher WiFi — quick guide

## Turn OFF Launcher WiFi (back to personal hotspot / Pi Connect)

**If you can SSH while on Launcher WiFi** (phone on Launcher, no internet OK):

```bash
ssh dtcteam2@192.168.4.1
cd ~/projects/Launcher
sudo bash wifi.sh off
sudo reboot
```

**If you have keyboard + monitor on the Pi:**

```bash
cd ~/projects/Launcher
sudo bash wifi.sh off
sudo reboot
```

After reboot, connect the Pi to your personal hotspot (WiFi menu or):

```bash
nmcli device wifi connect "YOUR_HOTSPOT_NAME" password "YOUR_PASSWORD"
```

Then Raspberry Pi Connect and normal SSH work again.

---

## Turn ON Launcher WiFi (demo / HUD)

```bash
cd ~/projects/Launcher
sudo bash wifi.sh on
```

Phone joins **Launcher** / password **Launcher** → http://192.168.4.1

**By default, AP turns off after reboot** so you are not stuck without Connect.

---

## Commands

| Command | Effect |
|---------|--------|
| `sudo bash wifi.sh on` | AP on now, **off after reboot** |
| `sudo bash wifi.sh on --boot` | AP on now **and every reboot** |
| `sudo bash wifi.sh off` | AP off, **no auto-start**, normal WiFi |
| `sudo bash wifi.sh status` | Check AP / boot setting |

---

## Fix AP that still starts on every boot (one time)

```bash
sudo systemctl disable hostapd dnsmasq
sudo rm -f /etc/launcher/ap-on-boot
sudo bash wifi.sh off
sudo reboot
```
