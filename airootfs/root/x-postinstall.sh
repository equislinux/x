#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────
# x postinstall: Branding, Configs, DE Settings
# Uses only packages/assets installed into /mnt.
# No remote downloads.
# ────────────────────────────────────────────────

# 0) Verify /mnt
if ! mountpoint -q /mnt; then
  echo "[x] Error: /mnt is not mounted. Did the installer finish successfully?"
  exit 1
fi

echo "[x] Starting Post-Install Configuration..."

# Helper: chroot execution
in_chroot() {
  arch-chroot /mnt sh -c "$1"
}

# 1) System Identity (/etc/os-release) — handled by the x-release package
#    (its post_install runs x-release-apply). Nothing to do here.

# 2) Asset paths (wallpapers installed by the x-wallpapers package)
WALL="x-wallpaper.png"
WALL_PATH="/usr/share/backgrounds/x/$WALL"
ASSET_WALL="/mnt$WALL_PATH"

if [ ! -f "$ASSET_WALL" ]; then
  echo "[x] Warning: wallpaper not found at $ASSET_WALL (x-wallpapers not installed?)"
fi

# 3) GNOME Branding
if in_chroot "pacman -Qq gnome-shell" >/dev/null 2>&1 || [ -d /mnt/usr/share/gnome-shell ]; then
  echo "[x] Applying GNOME Branding..."

  # Register wallpaper so it shows up in "Background" settings
  install -d /mnt/usr/share/gnome-background-properties
  cat > /mnt/usr/share/gnome-background-properties/x-wallpapers.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE wallpapers SYSTEM "gnome-wp-list.dtd">
<wallpapers>
  <wallpaper deleted="false">
    <name>x Default</name>
    <filename>$WALL_PATH</filename>
    <options>zoom</options>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
</wallpapers>
EOF

  # GSchema Overrides
  install -d /mnt/usr/share/glib-2.0/schemas
  cat > /mnt/usr/share/glib-2.0/schemas/99-x-branding.gschema.override <<EOF
[org.gnome.desktop.background]
picture-uri='file://$WALL_PATH'
picture-uri-dark='file://$WALL_PATH'
picture-options='zoom'
primary-color='#000000'
secondary-color='#000000'

[org.gnome.login-screen]
logo='/usr/share/pixmaps/x-logo.png'

[org.gnome.desktop.interface]
color-scheme='prefer-dark'
EOF

  # Recompile schemas
  if in_chroot "command -v glib-compile-schemas" >/dev/null 2>&1; then
    in_chroot "glib-compile-schemas /usr/share/glib-2.0/schemas/"
  fi
fi

# 4) KDE Plasma Branding
# Check for plasma-desktop package or plasma directory
if in_chroot "pacman -Qq plasma-desktop" >/dev/null 2>&1 || [ -d /mnt/usr/share/plasma ]; then
  echo "[x] Applying KDE Plasma Branding..."
  install -d /mnt/etc/xdg

  # Global wallpaper override
  cat > /mnt/etc/xdg/plasma-org.kde.plasma.desktop-appletsrc <<EOF
[Containments][1][Wallpaper][org.kde.image][General]
Image=file://$WALL_PATH
EOF

  # Lock screen
  cat > /mnt/etc/xdg/kscreenlockerrc <<EOF
[Greeter][Wallpaper][org.kde.image][General]
Image=file://$WALL_PATH
EOF
fi

# 5) XFCE Branding
# Check for xfce4-session package or xfce4 directory
if in_chroot "pacman -Qq xfce4-session" >/dev/null 2>&1 || [ -d /mnt/usr/share/xfce4 ]; then
  echo "[x] Applying XFCE Branding..."
  install -d /mnt/etc/xdg/xfce4/xfconf/xfce-perchannel-xml
  cat > /mnt/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="$WALL_PATH"/>
        </property>
      </property>
    </property>
  </property>
</channel>
EOF
fi

# 6) Display Manager Configuration

# SDDM (KDE default)
if in_chroot "command -v sddm" >/dev/null 2>&1; then
  echo "[x] Configuring SDDM..."
  install -d /mnt/etc/sddm.conf.d
  cat > /mnt/etc/sddm.conf.d/theme.conf <<EOF
[Theme]
Current=breeze
EOF
fi

# LightDM (XFCE default)
if in_chroot "command -v lightdm" >/dev/null 2>&1; then
  echo "[x] Configuring LightDM..."
  install -d /mnt/etc/lightdm
  cat > /mnt/etc/lightdm/lightdm-gtk-greeter.conf <<EOF
[greeter]
background=$WALL_PATH
icon-theme-name=Adwaita
font-name=Sans 10
EOF
fi

# GDM (GNOME default)
# GDM picks up the org.gnome.login-screen schema override set above.

# 8) First Boot Service (runs local x-dev-env, no remote downloads)
echo "[x] Setting up first-boot terminal hook..."

# 8.1 Create the script that runs on first terminal launch
install -d /mnt/usr/local/bin
cat > /mnt/usr/local/bin/x-first-terminal.sh <<'EOS'
#!/bin/sh
set -eu
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/x"
STATE="$STATE_DIR/firstterminal.done"
mkdir -p "$STATE_DIR"

# If already run, exit
[ -f "$STATE" ] && exit 0

printf "\n──────────────────────────────────────────\n"
printf "   Finalizing x Configuration\n"
printf "──────────────────────────────────────────\n\n"

# Enforce Wallpaper
WALL="/usr/share/backgrounds/x/x-wallpaper.png"
DESKTOP="${XDG_CURRENT_DESKTOP:-}"

if [ -f "$WALL" ]; then
    case "$DESKTOP" in
        *KDE*)
            if command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
                echo "→ Applying KDE Wallpaper..."
                plasma-apply-wallpaperimage "$WALL" || true
            fi
            ;;
        *XFCE*)
            if command -v xfconf-query >/dev/null 2>&1; then
                echo "→ Applying XFCE Wallpaper..."
                for property in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep "last-image"); do
                    xfconf-query -c xfce4-desktop -p "$property" -s "$WALL" || true
                done
                for property in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep "image-path"); do
                    xfconf-query -c xfce4-desktop -p "$property" -s "$WALL" || true
                done
            fi
            ;;
    esac
fi

# Run the local X development environment setup (installed by the x-dev package).
if command -v x-dev-env >/dev/null 2>&1; then
    echo "→ Running local post-install setup (x-dev-env)..."
    x-dev-env || echo "Warning: x-dev-env returned error status."
else
    echo "x-dev-env not found. Install the x-dev package to complete setup."
fi

# Mark as done so it doesn't run again
touch "$STATE"

# Remove the Autostart entry
if [ -f "$HOME/.config/autostart/x-firstboot.desktop" ]; then
    rm -f "$HOME/.config/autostart/x-firstboot.desktop"
fi

echo
echo "x configuration finished."
sleep 3
exit 0
EOS
chmod +x /mnt/usr/local/bin/x-first-terminal.sh

# 8.2 Create the XDG Autostart entry
# We put it in skel so it is copied to new users, and can be deleted by the user script.
install -d /mnt/etc/skel/.config/autostart
cat > /mnt/etc/skel/.config/autostart/x-firstboot.desktop <<EOF
[Desktop Entry]
Type=Application
Name=x Setup
Comment=Finalize x Installation
Exec=ptyxis -- /usr/local/bin/x-first-terminal.sh
Icon=utilities-terminal
Terminal=false
StartupNotify=true
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

# 8.3 Apply to existing users (created by the installer)
for user_home in /mnt/home/*; do
  [ -d "$user_home" ] || continue
  user_name=$(basename "$user_home")

  install -d "$user_home/.config/autostart"
  cp /mnt/etc/skel/.config/autostart/x-firstboot.desktop "$user_home/.config/autostart/"
  chown -R "$user_name:$user_name" "$user_home/.config/autostart"
done

echo "[x] Post-install finished successfully."
exit 0
