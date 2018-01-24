/*
 * Copyright (c) 2013-2016 Meltytech, LLC
 * Author: Dan Dennedy <dan@dennedy.org>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.6
import QtQuick.Controls 2.2
import QtQuick.Controls 1.4 as OLD
import Kdenlive.Controls 1.0
import QtGraphicalEffects 1.0
import QtQml.Models 2.2
import QtQuick.Window 2.2
import 'Timeline.js' as Logic

Rectangle {
    id: clipRoot
    property real timeScale: 1.0
    property string clipName: ''
    property string clipResource: ''
    property string mltService: ''
    property int modelStart: x
    property int scrollX: 0
    property int inPoint: 0
    property int outPoint: 0
    property int clipDuration: 0
    property bool isAudio: false
    property bool isComposition: false
    property bool showKeyframes: false
    property bool grouped: false
    property var audioLevels
    property var markers
    property var keyframeModel
    property int clipStatus
    property int fadeIn: 0
    property int fadeOut: 0
    property int binId: 0
    property var parentTrack: trackRoot
    property int trackIndex //Index in track repeater
    property int trackId: -42    //Id in the model
    property int clipId     //Id of the clip in the model
    property int originalTrackId: trackId
    property int originalX: x
    property int originalDuration: clipDuration
    property int lastValidDuration: clipDuration
    property int draggedX: x
    property bool selected: false
    property bool hasAudio
    property string hash: 'ccc' //TODO
    property double speed: 1.0
    property color borderColor: 'black'
    property bool reloadThumb: false
    width : clipDuration * timeScale;

    signal clicked(var clip, int shiftClick)
    signal moved(var clip)
    signal dragged(var clip, var mouse)
    signal dropped(var clip)
    signal draggedToTrack(var clip, int pos, int xpos)
    signal trimmingIn(var clip, real newDuration, var mouse)
    signal trimmedIn(var clip)
    signal trimmingOut(var clip, real newDuration, var mouse)
    signal trimmedOut(var clip)

    onGroupedChanged: {
        //console.log('Clip ', clipId, ' is grouped : ', grouped)
        //flashclip.start()
    }

    SequentialAnimation on color {
        id: flashclip
        loops: 2
        running: false
        ColorAnimation { from: Qt.darker(getColor()); to: "#ff3300"; duration: 100 }
        ColorAnimation { from: "#ff3300"; to: Qt.darker(getColor()); duration: 100 }
    }

    ToolTip {
        visible: mouseArea.containsMouse && !mouseArea.pressed
        font.pixelSize: root.baseUnit
        delay: 1000
        timeout: 5000
        background: Rectangle {
            color: activePalette.alternateBase
            border.color: activePalette.light
        }
        contentItem: Label {
            color: activePalette.text
            text: clipRoot.clipName + ' (' + timeline.timecode(clipRoot.inPoint) + '-' + timeline.timecode(clipRoot.outPoint) + ')'
        }
    }

    onKeyframeModelChanged: {
        console.log('keyframe model changed............')
        if (effectRow.keyframecanvas) {
            effectRow.keyframecanvas.requestPaint()
        }
    }

    onClipDurationChanged: {
        width = clipDuration * timeScale;
    }
    onModelStartChanged: {
        x = modelStart * timeScale;
    }
    onReloadThumbChanged: {
        if (mltService === 'color') {
            var newColor = getColor()
            color = selected ? newColor : Qt.darker(newColor)
        }
    }

    onTimeScaleChanged: {
        x = modelStart * timeScale;
        width = clipDuration * timeScale;
        labelRect.x = scrollX > modelStart * timeScale ? scrollX - modelStart * timeScale : 0
        generateWaveform();
    }
    onScrollXChanged: {
        labelRect.x = scrollX > modelStart * timeScale ? scrollX - modelStart * timeScale : 0
    }

    SystemPalette { id: activePalette }
    color: Qt.darker(getColor())

    border.color: selected? 'red' : grouped ? 'yellow' : borderColor
    border.width: 1.5
    Drag.active: mouseArea.drag.active
    Drag.proposedAction: Qt.MoveAction
    opacity: Drag.active? 0.5 : 1.0

    function getColor() {
        if (mltService === 'color') {
            //console.log('clip color', clipResource, " / ", '#' + clipResource.substring(3, 9))
            if (clipResource.length == 10) {
                // 0xRRGGBBAA
                return '#' + clipResource.substring(2, 8)
            } else if (clipResource.length == 9) {
                // 0xAARRGGBB
                return '#' + clipResource.substring(3, 9)
            }
        }
        return isAudio? '#445f5a' : '#416e8c'
        //root.shotcutBlue
    }

    function reparent(track) {
        console.log('TrackId: ',trackId)
        parent = track
        height = track.height
        parentTrack = track
        trackId = parentTrack.trackId
        //console.log('Reparenting clip to Track: ', trackId)
        //generateWaveform()
    }

    function generateWaveform() {
        // This is needed to make the model have the correct count.
        // Model as a property expression is not working in all cases.
        if (timeline.showAudioThumbnails) {
            waveformRepeater.model = Math.ceil(waveform.innerWidth / waveform.maxWidth)
            for (var i = 0; i < waveformRepeater.count; i++) {
                // This looks suspicious. Why not itemAt(i) ?? code borrowed from Shotcut
                waveformRepeater.itemAt(i).update();
            }
        }
    }

    function imagePath(time) {
        if (isAudio || mltService === 'color' || mltService === '') {
            return ''
        } else {
            console.log('get clip thumb for service: ', mltService)
            return 'image://thumbnail/' + binId + '/' + mltService + '/' + clipResource + '#' + time
        }
    }

    DropArea { //Drop area for clips
        anchors.fill: clipRoot
        keys: 'kdenlive/effect'
        property string dropData
        property string dropSource
        property int dropRow: -1
        onEntered: {
            dropData = drag.getDataAsString('kdenlive/effect')
            dropSource = drag.getDataAsString('kdenlive/effectsource')
        }
        onDropped: {
            console.log("Add effect: ", dropData)
            if (dropSource == '') {
                // drop from effects list
                controller.addClipEffect(clipRoot.clipId, dropData);
            } else {
                controller.copyClipEffect(clipRoot.clipId, dropSource);
            }
            dropSource = ''
            dropRow = -1
            drag.acceptProposedAction
        }
    }

    onAudioLevelsChanged: generateWaveform()
    MouseArea {
        id: mouseArea
        visible: root.activeTool === 0
        anchors.fill: clipRoot
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        drag.target: parent
        drag.axis: Drag.XAxis
        property int startX
        drag.smoothed: false
        hoverEnabled: true
        cursorShape: containsMouse ? pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor : tracksArea.cursorShape
        onPressed: {
            root.stopScrolling = true
            originalX = parent.x
            originalTrackId = clipRoot.trackId
            startX = parent.x
            root.stopScrolling = true
            clipRoot.forceActiveFocus();
            if (!clipRoot.selected) {
                clipRoot.clicked(clipRoot, mouse.modifiers == Qt.ShiftModifier)
            }
            drag.target = clipRoot
        }
        onPositionChanged: {
            if (pressed) {
                if (mouse.y < 0 || mouse.y > height) {
                    var mapped = parentTrack.mapFromItem(clipRoot, mouse.x, mouse.y).x
                    clipRoot.draggedToTrack(clipRoot, mapToItem(null, 0, mouse.y).y, mapped)
                } else {
                    clipRoot.dragged(clipRoot, mouse)
                }
            }
        }
        onReleased: {
            root.stopScrolling = false
            var delta = parent.x - startX
            drag.target = undefined
            cursorShape = Qt.OpenHandCursor
            if (trackId !== originalTrackId) {
                var track = Logic.getTrackById(trackId)
                parent.moved(clipRoot)
                reparent(track)
                originalX = parent.x
                clipRoot.y = 0
                originalTrackId = trackId
            } else {
                parent.dropped(clipRoot)
                originalX = parent.x
            }
        }
        onClicked: {
            if (mouse.button == Qt.RightButton) {
                menu.popup()
            }
        }
        onDoubleClicked: {
            if (showKeyframes) {
                // Add new keyframe
                var xPos = mouse.x  / timeline.scaleFactor
                var yPos = (clipRoot.height - mouse.y) / clipRoot.height
                keyframeModel.addKeyframe(xPos, yPos)
            } else {
                timeline.position = clipRoot.x / timeline.scaleFactor
            }
        }
        onWheel: zoomByWheel(wheel)
    }

    Item {
        // Clipping container
        id: container
        anchors.fill: parent
        anchors.margins:1.5
        clip: true
        Image {
            id: outThumbnail
            visible: timeline.showThumbnails && mltService != 'color' && !isAudio && clipStatus < 2
            opacity: parentTrack.isAudio || parentTrack.isHidden ? 0.2 : 1
            anchors.top: container.top
            anchors.right: container.right
            anchors.bottom: container.bottom
            width: height * 16.0/9.0
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            source: imagePath(outPoint)
        }

        Image {
            id: inThumbnail
            visible: timeline.showThumbnails && mltService != 'color' && !isAudio && clipStatus < 2
            opacity: parentTrack.isAudio || parentTrack.isHidden ? 0.2 : 1
            anchors.left: container.left
            anchors.bottom: container.bottom
            anchors.top: container.top
            width: height * 16.0/9.0
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            source: imagePath(inPoint)
        }

        Row {
            id: waveform
            visible: hasAudio && timeline.showAudioThumbnails  && !parentTrack.isMute && (clipStatus == 0 || clipStatus == 2)
            height: isAudio || parentTrack.isAudio || clipStatus == 2 ? container.height - 1 : (container.height - 1) / 2
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: container.bottom
            property int maxWidth: 1000
            property int innerWidth: clipRoot.width - clipRoot.border.width * 2
            property int scrollEnd: ((scrollView.flickableItem.contentX + scrollView.width) / timeScale - clipRoot.modelStart) * timeScale
            property int scrollStart: (scrollView.flickableItem.contentX / timeScale - clipRoot.modelStart) * timeScale

            Repeater {
                id: waveformRepeater
                TimelineWaveform {
                    width: Math.min(waveform.innerWidth, waveform.maxWidth)
                    height: waveform.height
                    showItem: (index * waveform.maxWidth) < waveform.scrollEnd && (index * waveform.maxWidth + width) > waveform.scrollStart
                    fillColor: 'red'
                    format: timeline.audioThumbFormat
                    property int channels: 2
                    inPoint: Math.round((clipRoot.inPoint + index * waveform.maxWidth / timeScale) * speed) * channels
                    outPoint: inPoint + Math.round(width / timeScale * speed) * channels
                    levels: audioLevels
                }
            }
        }

        Rectangle {
            // text background
            id: labelRect
            color: clipRoot.selected ? 'darkred' : '#66000000'
            width: label.width + 2
            height: label.height
            visible: clipRoot.width > width / 2
            Text {
                id: label
                text: clipName
                font.pixelSize: root.baseUnit
                anchors {
                    top: parent.top
                    left: parent.left
                    topMargin: 1
                    leftMargin: 1
                    // + ((isAudio || !settings.timelineShowThumbnails) ? 0 : inThumbnail.width) + 1
                }
                color: 'white'
                style: Text.Outline
                styleColor: 'black'
            }
        }

        Repeater {
            model: markers
            delegate:
            Item {
                anchors.fill: parent
                Rectangle {
                    id: markerBase
                    width: 1
                    height: parent.height
                    x: (model.frame - clipRoot.inPoint) * timeScale;
                    color: model.color
                }
                Rectangle {
                    visible: mlabel.visible
                    opacity: 0.7
                    x: markerBase.x
                    radius: 2
                    width: mlabel.width + 4
                    height: mlabel.height
                    anchors {
                        bottom: parent.verticalCenter
                    }
                    color: model.color
                    MouseArea {
                        z: 10
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onDoubleClicked: timeline.editMarker(clipRoot.binId, model.frame)
                        onClicked: timeline.position = (clipRoot.x + markerBase.x) / timeline.scaleFactor
                    }
                }
                Text {
                    id: mlabel
                    visible: timeline.showMarkers && parent.width > width * 1.5
                    text: model.comment
                    font.pixelSize: root.baseUnit
                    x: markerBase.x
                    anchors {
                        bottom: parent.verticalCenter
                        topMargin: 2
                        leftMargin: 2
                    }
                    color: 'white'
                }
            }
        }

        KeyframeView {
            id: effectRow
            visible: clipRoot.showKeyframes && keyframeModel
            inPoint: clipRoot.inPoint
            outPoint: clipRoot.outPoint
        }
    }

    states: [
        State {
            name: 'normal'
            when: clipRoot.selected === false
            PropertyChanges {
                target: clipRoot
                color: Qt.darker(getColor())
            }
        },
        State {
            name: 'selected'
            when: clipRoot.selected === true
            PropertyChanges {
                target: clipRoot
                z: 1
                color: getColor()
            }
        }
    ]


    TimelineTriangle {
        id: fadeInTriangle
        width: clipRoot.fadeIn * timeScale
        height: clipRoot.height - clipRoot.border.width * 2
        anchors.left: clipRoot.left
        anchors.top: clipRoot.top
        anchors.margins: clipRoot.border.width
        opacity: 0.3
    }
    Rectangle {
        id: fadeInControl
        anchors.left: fadeInTriangle.width > radius? undefined : fadeInTriangle.left
        anchors.horizontalCenter: fadeInTriangle.width > radius? fadeInTriangle.right : undefined
        anchors.top: fadeInTriangle.top
        anchors.topMargin: -10
        width: root.baseUnit * 2
        height: width
        radius: width / 2
        color: '#66FFFFFF'
        border.width: 2
        border.color: 'red'
        opacity: 0
        Drag.active: fadeInMouseArea.drag.active
        MouseArea {
            id: fadeInMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            drag.target: parent
            drag.axis: Drag.XAxis
            property int startX
            property int startFadeIn
            onEntered: parent.opacity = 0.7
            onExited: {
                if (!pressed) {
                  parent.opacity = 0
                }
            }
            drag.smoothed: false
            onPressed: {
                root.stopScrolling = true
                startX = parent.x
                startFadeIn = clipRoot.fadeIn
                parent.anchors.left = undefined
                parent.anchors.horizontalCenter = undefined
                parent.opacity = 1
                fadeInTriangle.opacity = 0.5
                // parentTrack.clipSelected(clipRoot, parentTrack) TODO
            }
            onReleased: {
                root.stopScrolling = false
                fadeInTriangle.opacity = 0.3
                parent.opacity = 0
                if (fadeInTriangle.width > parent.radius)
                    parent.anchors.horizontalCenter = fadeInTriangle.right
                else
                    parent.anchors.left = fadeInTriangle.left
                timeline.adjustFade(clipRoot.clipId, 'fadein', clipRoot.fadeIn, startFadeIn)
                bubbleHelp.hide()
            }
            onPositionChanged: {
                if (mouse.buttons === Qt.LeftButton) {
                    var delta = Math.round((parent.x - startX) / timeScale)
                    var duration = Math.max(0, startFadeIn + delta)
                    duration = Math.min(duration, clipRoot.clipDuration)
                    if (clipRoot.fadeIn != duration) {
                        clipRoot.fadeIn = duration
                        timeline.adjustFade(clipRoot.clipId, 'fadein', duration, -1)
                    }
                    // Show fade duration as time in a "bubble" help.
                    var s = timeline.timecode(Math.max(duration, 0))
                    bubbleHelp.show(clipRoot.x, parentTrack.y + clipRoot.height, s)
                }
            }
        }
        SequentialAnimation on scale {
            loops: Animation.Infinite
            running: fadeInMouseArea.containsMouse && !fadeInMouseArea.pressed
            NumberAnimation {
                from: 1.0
                to: 0.7
                duration: 250
                easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                from: 0.7
                to: 1.0
                duration: 250
                easing.type: Easing.InOutQuad
            }
        }
    }

    TimelineTriangle {
        id: fadeOutCanvas
        width: clipRoot.fadeOut * timeScale
        height: clipRoot.height - clipRoot.border.width * 2
        anchors.right: clipRoot.right
        anchors.top: clipRoot.top
        anchors.margins: clipRoot.border.width
        opacity: 0.3
        transform: Scale { xScale: -1; origin.x: fadeOutCanvas.width / 2}
    }
    Rectangle {
        id: fadeOutControl
        anchors.right: fadeOutCanvas.width > radius? undefined : fadeOutCanvas.right
        anchors.horizontalCenter: fadeOutCanvas.width > radius? fadeOutCanvas.left : undefined
        anchors.top: fadeOutCanvas.top
        anchors.topMargin: -10
        width: root.baseUnit * 2
        height: width
        radius: width / 2
        color: '#66FFFFFF'
        border.width: 2
        border.color: 'red'
        opacity: 0
        Drag.active: fadeOutMouseArea.drag.active
        MouseArea {
            id: fadeOutMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            drag.target: parent
            drag.axis: Drag.XAxis
            property int startX
            property int startFadeOut
            onEntered: parent.opacity = 0.7
            onExited: {
                if (!pressed) {
                  parent.opacity = 0
                }
            }
            drag.smoothed: false
            onPressed: {
                root.stopScrolling = true
                startX = parent.x
                startFadeOut = clipRoot.fadeOut
                parent.anchors.right = undefined
                parent.anchors.horizontalCenter = undefined
                parent.opacity = 1
                fadeOutCanvas.opacity = 0.5
            }
            onReleased: {
                fadeOutCanvas.opacity = 0.3
                parent.opacity = 0
                root.stopScrolling = false
                if (fadeOutCanvas.width > parent.radius)
                    parent.anchors.horizontalCenter = fadeOutCanvas.left
                else
                    parent.anchors.right = fadeOutCanvas.right
                timeline.adjustFade(clipRoot.clipId, 'fadeout', clipRoot.fadeOut, startFadeOut)
                bubbleHelp.hide()
            }
            onPositionChanged: {
                if (mouse.buttons === Qt.LeftButton) {
                    var delta = Math.round((startX - parent.x) / timeScale)
                    var duration = Math.max(0, startFadeOut + delta)
                    duration = Math.min(duration, clipRoot.clipDuration)
                    if (clipRoot.fadeOut != duration) {
                        clipRoot.fadeOut = duration
                        timeline.adjustFade(clipRoot.clipId, 'fadeout', duration, -1)
                    }
                    // Show fade duration as time in a "bubble" help.
                    var s = timeline.timecode(Math.max(duration, 0))
                    bubbleHelp.show(clipRoot.x + clipRoot.width, parentTrack.y + clipRoot.height, s)
                }
            }
        }
        SequentialAnimation on scale {
            loops: Animation.Infinite
            running: fadeOutMouseArea.containsMouse && !fadeOutMouseArea.pressed
            NumberAnimation {
                from: 1.0
                to: 0.7
                duration: 250
                easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                from: 0.7
                to: 1.0
                duration: 250
                easing.type: Easing.InOutQuad
            }
        }
    }

    Rectangle {
        id: trimIn
        anchors.left: parent.left
        anchors.leftMargin: 0
        height: parent.height
        width: 5
        color: isAudio? 'green' : 'lawngreen'
        opacity: 0
        Drag.active: trimInMouseArea.drag.active
        Drag.proposedAction: Qt.MoveAction
        visible: root.activeTool === 0 && !mouseArea.drag.active

        MouseArea {
            id: trimInMouseArea
            anchors.fill: parent
            hoverEnabled: true
            drag.target: parent
            drag.axis: Drag.XAxis
            drag.smoothed: false
            cursorShape: (containsMouse
                          ? (pressed
                             ? Qt.SizeHorCursor
                             : Qt.SizeHorCursor)
                          : Qt.ClosedHandCursor);
            onPressed: {
                root.stopScrolling = true
                clipRoot.originalX = clipRoot.x
                clipRoot.originalDuration = clipDuration
                parent.anchors.left = undefined
            }
            onReleased: {
                root.stopScrolling = false
                parent.anchors.left = clipRoot.left
                clipRoot.trimmedIn(clipRoot)
            }
            onPositionChanged: {
                if (mouse.buttons === Qt.LeftButton) {
                    var delta = Math.round((trimIn.x) / timeScale)
                    if (delta !== 0) {
                        var newDuration =  clipDuration - delta
                        clipRoot.trimmingIn(clipRoot, newDuration, mouse)
                    }
                }
            }
            onEntered: {
                parent.opacity = 0.5
            }
            onExited: {
                parent.opacity = 0
            }
        }
    }
    Rectangle {
        id: trimOut
        anchors.right: parent.right
        anchors.rightMargin: 0
        height: parent.height
        width: 5
        color: 'red'
        opacity: 0
        Drag.active: trimOutMouseArea.drag.active
        Drag.proposedAction: Qt.MoveAction
        visible: root.activeTool === 0 && !mouseArea.drag.active

        MouseArea {
            id: trimOutMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: (containsMouse
                          ? (pressed
                             ? Qt.SizeHorCursor
                             : Qt.SizeHorCursor)
                          : Qt.ClosedHandCursor);
            drag.target: parent
            drag.axis: Drag.XAxis
            drag.smoothed: false

            onPressed: {
                root.stopScrolling = true
                clipRoot.originalDuration = clipDuration
                parent.anchors.right = undefined
            }
            onReleased: {
                root.stopScrolling = false
                parent.anchors.right = clipRoot.right
                clipRoot.trimmedOut(clipRoot)
            }
            onPositionChanged: {
                if (mouse.buttons === Qt.LeftButton) {
                    var newDuration = Math.round((parent.x + parent.width) / timeScale)
                    if (newDuration != clipDuration) {
                        clipRoot.trimmingOut(clipRoot, newDuration, mouse)
                    }
                }
            }
            onEntered: parent.opacity = 0.5
            onExited: parent.opacity = 0
        }
    }
    OLD.Menu {
        id: menu
        function show() {
            //mergeItem.visible = timeline.mergeClipWithNext(trackIndex, index, true)
            menu.popup()
        }
        OLD.MenuItem {
            visible: true
            text: i18n('Cut')
            onTriggered: {
                console.log('cutting clip:', clipRoot.clipId)
                if (!parentTrack.isLocked) {
                    timeline.requestClipCut(clipRoot.clipId, timeline.position)
                } else {
                    root.pulseLockButtonOnTrack(currentTrack)
                }
            }
        }
        OLD.MenuItem {
            visible: !grouped && parentTrack.selection.length > 1
            text: i18n('Group')
            onTriggered: timeline.triggerAction('group_clip')
        }
        OLD.MenuItem {
            visible: grouped
            text: i18n('Ungroup')
            onTriggered: timeline.unGroupSelection(clipId)
        }

        OLD.MenuItem {
            visible: true
            text: i18n('Copy')
            onTriggered: root.copiedClip = clipRoot.clipId
        }
        OLD.MenuSeparator {
            visible: true
        }
        OLD.MenuItem {
            text: i18n('Split Audio')
            onTriggered: timeline.splitAudio(clipRoot.clipId)
            visible: clipStatus == 0
        }
        OLD.MenuItem {
            text: i18n('Remove')
            onTriggered: timeline.triggerAction('delete_timeline_clip')
        }
        OLD.MenuItem {
            visible: true
            text: i18n('Extract')
            onTriggered: timeline.extract(clipRoot.clipId)
        }
        OLD.MenuSeparator {
            visible: true
        }
        OLD.MenuItem {
            text: i18n('Clip in Project Bin')
            onTriggered: timeline.triggerAction('clip_in_project_tree')
        }
        OLD.MenuItem {
            visible: true
            text: i18n('Split At Playhead')
            onTriggered: timeline.triggerAction('cut_timeline_clip')
        }
        OLD.Menu {
            title: i18n('Clip Type...')
            OLD.ExclusiveGroup {
                id: radioInputGroup
            }
            OLD.MenuItem {
                text: i18n('Original')
                checkable: true
                checked: clipStatus == 0
                exclusiveGroup: radioInputGroup
                onTriggered: timeline.setClipStatus(clipRoot.clipId, 0)
            }
            OLD.MenuItem {
                text: i18n('Video Only')
                checkable: true
                checked: clipStatus == 1
                exclusiveGroup: radioInputGroup
                onTriggered: timeline.setClipStatus(clipRoot.clipId, 1)
            }
            OLD.MenuItem {
                text: i18n('Audio Only')
                checkable: true
                checked: clipStatus == 2
                exclusiveGroup: radioInputGroup
                onTriggered: timeline.setClipStatus(clipRoot.clipId, 2)
            }
            OLD.MenuItem {
                text: i18n('Disabled')
                checkable: true
                checked: clipStatus == 3
                exclusiveGroup: radioInputGroup
                onTriggered: timeline.setClipStatus(clipRoot.clipId, 3)
            }
        }
        /*MenuItem {
            id: mergeItem
            text: i18n('Merge with next clip')
            onTriggered: timeline.mergeClipWithNext(trackIndex, index, false)
        }
        MenuItem {
            text: i18n('Rebuild Audio Waveform')
            onTriggered: timeline.remakeAudioLevels(trackIndex, index)
        }*/
        /*onPopupVisibleChanged: {
            if (visible && application.OS !== 'OS X' && __popupGeometry.height > 0) {
                // Try to fix menu running off screen. This only works intermittently.
                menu.__yOffset = Math.min(0, Screen.height - (__popupGeometry.y + __popupGeometry.height + 40))
                menu.__xOffset = Math.min(0, Screen.width - (__popupGeometry.x + __popupGeometry.width))
            }
        }*/
    }
}