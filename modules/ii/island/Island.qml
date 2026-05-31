pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common

Scope {
    id: island

    Variants {
        // For each monitor
        model: {
            const screens = Quickshell.screens;
            const list = Config.options.island.screenList;
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.includes(screen.name));
        }
        LazyLoader {
            id: islandLoader
            active: !GlobalStates.screenLocked
            required property ShellScreen modelData
            component: PanelWindow {
                id: islandRoot
                screen: islandLoader.modelData

                // Island window — transparent, top layer, no keyboard focus
                WlrLayershell.namespace: "quickshell:island"
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                exclusiveZone: 10 + 120 + 10

                anchors {
                    top: true
                    left: true
                    right: true
                }

                margins {
                    top: 10
                    left: 10
                    right: 10
                }

                implicitHeight: 120
                color: "transparent"

                MouseArea {
                    id: hoverRegion
                    anchors.fill: parent
                    hoverEnabled: true

                    IslandContent {
                        id: islandContent
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 15
                    }
                }
            }
        }
    }
}
