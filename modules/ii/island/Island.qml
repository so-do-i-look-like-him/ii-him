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

    property int screenGap: 6

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
                exclusiveZone: island.screenGap + 44 + island.screenGap

                anchors {
                    top: true
                    left: true
                    right: true
                }

                implicitHeight: island.screenGap + 44 + island.screenGap
                color: "transparent"

                MouseArea {
                    id: hoverRegion
                    anchors.fill: parent

                    IslandContent {
                        id: islandContent
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }
}
