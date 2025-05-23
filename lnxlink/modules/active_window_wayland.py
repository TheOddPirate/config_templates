from lnxlink.modules.scripts.helpers import (
    import_install_package,
    syscommand
)
import logging
import subprocess
import ast
import json
import os

logger = logging.getLogger("lnxlink")

class Addon:
    """Addon module"""

    def __init__(self, lnxlink):
        """Setup addon"""
        self.name = "Active Window"
        self.lnxlink = lnxlink
        self.use_original = self.is_usable()
        self._requirements()
        
#function to install missing pip packages
    def _requirements(self):
        if self.use_original:
            self.lib = {
                "ewmh": import_install_package("ewmh", ">=0.1.6"),
                "xlib": import_install_package("python-xlib", ">=0.33", "Xlib.display"),
                }
        else:
            self.jeepney = import_install_package(
                "jeepney",
                ">=0.9.0",
                (
                    "jeepney",
                    [
                        "DBusAddress",
                        "new_method_call",
                        "io.blocking.open_dbus_connection",
                    ],
                ),
            )
            if not self._is_extension_installed():
                logger.info("Installing focused-window-dbus extension...")
                self.gnome_ext = import_install_package(
                    "gnome-extensions-cli",
                    ">=0.3.0",
                    (       
                        "gnome_extensions_cli",
                        ["GnomeExtensions"],
                    ),
                )
                try:
                    ge = self.gnome_ext.GnomeExtensions()
                    extension_uuid = "focused-window-dbus@flexagoon.com"
                    # Install the extension
                    ge.install(extension_uuid)
                    # Enable the extension
                    ge.enable(extension_uuid)
                    logger.info("Extension installed and enabled successfully, you might need to reboot before it works")
                except Exception as e:
                    logger.error(f"Error installing extension: {e}")
        
    
    def is_usable(self):
        """Check desktop environment and display server"""
        # Check for Wayland
        wayland_display = os.environ.get('WAYLAND_DISPLAY')
        
        # Check desktop environment
        desktop = os.environ.get('XDG_CURRENT_DESKTOP', '').lower()
        session = os.environ.get('XDG_SESSION_TYPE', '').lower()
        
        logger.debug(f"Desktop environment: {desktop}")
        logger.debug(f"Session type: {session}")
        
        if 'gnome' in desktop:
            if wayland_display:
                logger.debug("Running GNOME with Wayland, using alternative method")
                return False
            else:
                logger.debug("Running GNOME with X11, using original method")
                return True
                
        elif 'kde' in desktop:
            if wayland_display:
                logger.debug("Running KDE with Wayland, not supported yet")
                return False
            else:
                logger.debug("Running KDE with X11, using original method")
                return True
                
        else:
            # Fallback for other desktop environments
            if wayland_display:
                logger.error("Running unknown DE with Wayland, not supported")
                return False
            else:
                logger.debug("Running unknown DE with X11, attempting original method")
                return True

 
    def _is_extension_installed(self, extension_name="focused-window-dbus@flexagoon.com"):
        stdout, stderr, returncode = syscommand(command='gnome-extensions list')
        if  returncode == 0:
            installed_extensions = stdout.split('\n')
            return extension_name in installed_extensions
        else:
            logger.error("Failed running the \"gnome-extensions list\" command")
            return False
            
    def exposed_controls(self):
        """Exposes to home assistant"""
        return {
            "Active Window": {
                "type": "sensor",
                "icon": "mdi:book-open-page-variant",
            },
        }

    def get_info(self):

        """Gather information from the system"""
        if self.use_original:
            if self.lnxlink.display is None:
                return ""
            display = self.lib["xlib"].display.Display(self.lnxlink.display)
            ewmh = self.lib["ewmh"].EWMH(_display=display)
            win = ewmh.getActiveWindow()
            window_name = ewmh.getWmName(win)
            if window_name is None:
                return None
            return window_name.decode()
        else:
            try:
                desktop = os.environ.get('XDG_CURRENT_DESKTOP', '').lower()
                connection = self.jeepney.io.blocking.open_dbus_connection(bus='SESSION')

                if 'kde' in desktop:
                    # KDE specific D-Bus call
                    address = self.jeepney.DBusAddress(
                        bus_name='org.kde.KWin',
                        object_path='/KWin',
                        interface='org.kde.KWin'
                    )
                    message = self.jeepney.new_method_call(address, 'activeWindow', '')
                    reply = connection.send_and_get_reply(message)
                    
                    # Get window title
                    window_id = reply.body[0]
                    message = self.jeepney.new_method_call(
                        address, 
                        'getWindowInfo', 
                        'u',  # unsigned int parameter
                        (window_id,)
                    )
                    reply = connection.send_and_get_reply(message)
                    window_info = json.loads(reply.body[0])
                    connection.close()
                    return window_info.get('caption', 'Unknown')

                elif 'gnome' in desktop:
                    try:
                        # Just try to get window info directly through the extension's D-Bus interface
                        window_address = self.jeepney.DBusAddress(
                            bus_name='org.gnome.Shell',
                            object_path='/org/gnome/shell/extensions/FocusedWindow',
                            interface='org.gnome.shell.extensions.FocusedWindow'
                        )
        
                        message = self.jeepney.new_method_call(
                            window_address,
                            'Get',
                            '',
                            ()
                        )
        
                        reply = connection.send_and_get_reply(message)
                        if reply.body:
                            try:
                                window_info = json.loads(reply.body[0])
                                title = window_info.get('title', '')
                                if title:
                                    connection.close()
                                    return title
                            except (json.JSONDecodeError, IndexError) as e:
                                logger.debug(f"Failed to parse window info: {e}")
        
                        connection.close()
                        return "No active window"
        
                    except Exception as e:
                        logger.debug(f"Error getting window info: {e}")
                        return "Unknown"

                connection.close()
                return "No active window"
            except Exception as e:
                logger.error(f"Error getting window info: {e}")
                return "Unknown"

