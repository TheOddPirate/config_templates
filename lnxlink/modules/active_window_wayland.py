"""
Gets the active window
This module checks the same way as lnxlink original module,
but it has a extra check to detect if you are on wayland
if you are on wayland and gnome it installs a gnome extension to allow you to find the 
active window title, if you are on x11 it used the default way that comes with lnxlink

we also tried to add a way to do this for kde, but as i am not a kde user, that was implemented with help 
from the llm claude and i need some feedback if it works or not
"""
from lnxlink.modules.scripts.helpers import import_install_package


class Addon:
    """Addon module"""

    def __init__(self, lnxlink):
        """Setup addon"""
        self.name = "Active Window"
        self.lnxlink = lnxlink
        self._requirements()

    def _requirements(self):
        self.lib = {
            "pywinctl": import_install_package("pywinctl", ">=0.4"),
        }

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
        win = self.lib["pywinctl"].getActiveWindow()
        if win is not None:
          print("ACTIVE WINDOW", win.title)
          return win.title
        display = self.lib["pywinctl"].getActiveWindowTitle()
        return display

