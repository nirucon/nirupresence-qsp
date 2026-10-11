import QtQuick 6.11
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "se.ilnr.nirupresence"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var statuses: []
  property string currentStatus: ""
  property string currentDetail: ""
  property bool online: false
  property bool manualOffline: false
  property string presenceMode: "unknown"
  property bool shareMusic: true
  property bool configured: false
  property bool apiOk: false
  property bool loading: false
  property string errorText: ""
  property string playerArtist: ""
  property string playerTitle: ""
  property bool playerPlaying: false
  property bool playerAvailable: true
  property string playerReason: ""
  property string playerSource: ""
  property string sessionSince: ""
  property string lastSeen: ""
  property bool nightMode: false
  property int tempUntil: 0
  property int tempMinutes: 0
  property string actionFeedback: ""
  property bool draftLoaded: false

  readonly property var barIdentity: hostWidget || root
  readonly property string helperPath: decodeURIComponent(Qt.resolvedUrl("nirupresence.py").toString().replace(/^file:\/\//, ""))
  readonly property string barTooltip: "NIRUPRESENCE · " + (manualOffline || !online ? "offline" : (currentStatus.length ? currentStatus : "online"))
  readonly property color popupBg: Color.popups.background
  readonly property color popupTextCandidate: Color.popups.text
  readonly property color baseTextCandidate: Color.foreground
  readonly property color accent: Color.accent

  function luminance(c) { function lin(x){return x<=0.03928?x/12.92:Math.pow((x+0.055)/1.055,2.4)}; return .2126*lin(c.r)+.7152*lin(c.g)+.0722*lin(c.b) }
  function contrast(a,b) { var x=luminance(a),y=luminance(b); return (Math.max(x,y)+.05)/(Math.min(x,y)+.05) }
  readonly property color fg: contrast(popupTextCandidate,popupBg)>=3 ? popupTextCandidate : (contrast(baseTextCandidate,popupBg)>=3 ? baseTextCandidate : (luminance(popupBg)<.5?"#f2f2f2":"#161616"))
  readonly property color mutedFg: Qt.rgba(fg.r,fg.g,fg.b,.60)
  readonly property color faintFg: Qt.rgba(fg.r,fg.g,fg.b,.28)
  readonly property color subtleFill: Qt.rgba(fg.r,fg.g,fg.b,.07)
  readonly property color hoverFill: Qt.rgba(fg.r,fg.g,fg.b,.13)
  function tempUntilText() { if(tempUntil<1) return ""; var d=new Date(tempUntil*1000); return ("0"+d.getHours()).slice(-2)+":"+("0"+d.getMinutes()).slice(-2) }

  function commandFor(args) { var c=["python3",helperPath]; for(var i=0;i<args.length;i++) c.push(args[i]); return c }
  function open() { controller.show(); refresh() }
  function close() { controller.hide() }
  function toggle() { opened ? close() : open() }
  function closeForPopoutSwitch() { close() }
  function switchPanel(direction) { if(bar&&typeof bar.switchPanelFrom==="function") return bar.switchPanelFrom(barIdentity,direction); return false }

  function refresh() {
    if (dashboardProcess.running) return
    loading=true; errorText=""
    dashboardProcess.command=commandFor(["dashboard"]); dashboardProcess.running=true
  }
  function parseDashboard(text) {
    try {
      var d=JSON.parse(text); loading=false
      if (d.error) { errorText=String(d.error); return }
      configured=!!d.configured; apiOk=!!d.api_ok; errorText=d.error||""
      statuses=d.statuses||[]
      var p=d["public"]||{}, l=d.local||{}, pl=d.player||{}, policy=d.policy||{}
      currentStatus=p.status||""; currentDetail=p.detail||""; online=!!p.online
      sessionSince=p.session_since||""; lastSeen=p.last_seen||""
      presenceMode=String(p.presence_mode || p.mode || "unknown").toLowerCase()
      manualOffline=presenceMode==="offline"; shareMusic=l.share_music!==false; nightMode=!!p.night_mode; tempUntil=Number((p.temporary||{}).until||0)
      playerPlaying=!!pl.playing; playerAvailable=pl.available!==false; playerReason=pl.reason||""; playerSource=pl.source||""; playerArtist=pl.artist||""; playerTitle=pl.title||""
      if (!detailInput.activeFocus) detailInput.text=currentDetail
      if (!draftLoaded && !microInput.activeFocus) { microInput.text=l.micro_draft||""; draftLoaded=true }
    } catch(e) { loading=false; errorText="Kunde inte läsa NIRUPRESENCE-data" }
  }
  function parseMusicSync(text) {
    try {
      var d=JSON.parse(text), pl=d.player||{}
      if (pl.available === undefined && d.presence) return
      playerPlaying=!!pl.playing; playerAvailable=pl.available!==false
      playerReason=pl.reason||""; playerSource=pl.source||""
      playerArtist=pl.artist||""; playerTitle=pl.title||""
    } catch(e) { /* A music poll must never blank or break the panel. */ }
  }
  function runAction(args, refreshAfter, feedback) {
    if (actionProcess.running) return
    errorText=""; actionFeedback=""; pendingFeedback=feedback||""; actionRefresh=refreshAfter!==false
    actionProcess.command=commandFor(args); actionProcess.running=true
  }
  property bool actionRefresh: true
  property string pendingFeedback: ""
  function setStatus(value) {
    if (tempMinutes>0) runAction(["temp-status",value,String(tempMinutes),detailInput.text.trim()],true,"Tillfällig status satt")
    else runAction(["status",value,detailInput.text.trim()],true,"Status uppdaterad")

  }
  function saveDetail() { runAction(["status",currentStatus,detailInput.text.trim()],true,"Detalj sparad") }
  function clearDetail() { runAction(["status",currentStatus,""],true,"Detalj rensad") }
  function cancelTemp() { runAction(["cancel-temp"],true,"Tillfällig status avslutad") }
  function setPresenceMode(mode) { runAction(["mode",mode],true,"Närvaroläge uppdaterat") }
  function toggleMusic() { runAction(["share-music",shareMusic?"false":"true"],true,shareMusic?"Musikdelning av":"Musikdelning på") }
  function publishMicrolog() {
    var body=microInput.text.trim(); if(!body.length||body.length>1000) return
    if (microProcess.running) return
    errorText=""; microProcess.command=commandFor(["microlog",body]); microProcess.running=true
  }
  function saveDraft() { if(!draftLoaded||draftProcess.running) return; draftProcess.command=commandFor(["draft",microInput.text]); draftProcess.running=true }
  function clearMicro() { microInput.text=""; draftTimer.stop(); if(!draftProcess.running){draftProcess.command=commandFor(["draft",""]);draftProcess.running=true}; microFeedback.text="Utkast rensat"; microFeedbackTimer.restart() }

  Process { id: dashboardProcess; stdout: StdioCollector { waitForEnd:true; onStreamFinished: root.parseDashboard(this.text) } }
  Process { id: actionProcess; stdout: StdioCollector { waitForEnd:true; onStreamFinished: {
    try { var d=JSON.parse(this.text); if(d.error || d.ok===false) { root.errorText=String(d.error||"Servern bekräftade inte åtgärden"); root.actionFeedback="" } else { root.actionFeedback=root.pendingFeedback; feedbackTimer.restart(); if(root.actionRefresh) root.refresh() } }
    catch(e){root.errorText="Åtgärden kunde inte slutföras"}
  }}}
  Process { id: microProcess; stdout: StdioCollector { waitForEnd:true; onStreamFinished: {
    try { var d=JSON.parse(this.text); if(d.error) root.errorText=String(d.error); else { microInput.text=""; microFeedback.text="Publicerad just nu"; microFeedbackTimer.restart() } }
    catch(e){root.errorText="Microlog kunde inte publiceras"}
  }}}
  Process { id: heartbeatProcess }
  Process { id: draftProcess }
  Process { id: musicProcess; stdout: StdioCollector { waitForEnd:true; onStreamFinished: root.parseMusicSync(this.text) } }

  Timer { interval:300000; repeat:true; running:true; triggeredOnStart:true; onTriggered: {
    if(!heartbeatProcess.running) { heartbeatProcess.command=root.commandFor(["heartbeat"]); heartbeatProcess.running=true }
  }}
  Timer { interval:10000; repeat:true; running:true; triggeredOnStart:true; onTriggered: {
    // 10 s gives near-live track changes. The running guard prevents overlapping sync processes.
    if(!musicProcess.running) { musicProcess.command=root.commandFor(["sync-music"]); musicProcess.running=true }
  }}
  Timer { interval:30000; repeat:true; running:root.opened; onTriggered:root.refresh() }
  Timer { id: microFeedbackTimer; interval:3500; onTriggered: microFeedback.text="" }
  Timer { id: feedbackTimer; interval:2500; onTriggered: root.actionFeedback="" }
  Timer { id: draftTimer; interval:900; onTriggered: root.saveDraft() }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem; owner: root.barIdentity; bar: root.bar; open: root.opened
    centerOnBar:false; focusTarget:keyCatcher
    contentWidth: popup.fittedContentWidth(460)
    contentHeight: popup.fittedContentHeight(610)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: detailInput.activeFocus || microInput.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction){root.switchPanel(direction)}
      Keys.onPressed: function(event) {
        if (blocked) return
        if (event.key===Qt.Key_R) { root.refresh(); event.accepted=true }
        else if (event.key===Qt.Key_A) { root.setPresenceMode("auto"); event.accepted=true }
        else if (event.key===Qt.Key_O) { root.setPresenceMode("online"); event.accepted=true }
        else if (event.key===Qt.Key_F) { root.setPresenceMode("offline"); event.accepted=true }
        else if (event.key===Qt.Key_M) { root.toggleMusic(); event.accepted=true }
        else if (event.key===Qt.Key_Slash) { detailInput.forceActiveFocus(); event.accepted=true }
        else if (event.key>=Qt.Key_1 && event.key<=Qt.Key_9) { var i=event.key-Qt.Key_1; if(i<root.statuses.length){root.setStatus(root.statuses[i]);event.accepted=true} }
      }

      Item {
        anchors.fill: parent
        Column {
          anchors.fill: parent
          spacing: 8

          Row {
            width:parent.width; height:38; spacing:8
            Column {
              width:parent.width-44; spacing:1
              Text { text:"NIRUPRESENCE"; color:root.fg; font.bold:true; font.pixelSize:17 }
              Text { width:parent.width; text: !root.configured ? "API ej konfigurerat" : (root.apiOk ? "n.rudolfsson.net · ansluten" : "n.rudolfsson.net · offline"); color:root.mutedFg; font.pixelSize:10; elide:Text.ElideRight }
            }
            Rectangle {
              width:34; height:30; radius:6; color:refreshMouse.containsMouse?root.hoverFill:root.subtleFill
              Text { anchors.centerIn:parent; text:root.loading?"…":"↻"; color:root.fg; font.pixelSize:16 }
              MouseArea { id:refreshMouse; anchors.fill:parent; hoverEnabled:true; enabled:!root.loading; cursorShape:Qt.PointingHandCursor; onClicked:root.refresh() }
            }
          }
          Rectangle { width:parent.width; height:1; color:root.faintFg }

          Rectangle {
            width:parent.width; height:visible?42:0; visible:root.errorText.length>0 || !root.configured; radius:6; color:root.subtleFill
            Text { anchors.fill:parent; anchors.margins:8; color:root.fg; font.pixelSize:10; wrapMode:Text.WordWrap; text:root.configured?root.errorText:"Skapa API-nyckel i webbadmin och kör configure enligt README." }
          }

          Row { width:parent.width; height:16
            Text { text:"STATUS"; color:root.mutedFg; font.bold:true; font.pixelSize:10 }
            Text { anchors.right:parent.right; text:root.actionFeedback; color:root.mutedFg; font.pixelSize:9 }
          }
          Flow {
            width:parent.width; spacing:5
            Repeater {
              model: [""].concat(root.statuses)
              delegate: Rectangle {
                required property string modelData
                width: Math.min(parent.width, statusLabel.implicitWidth+20); height:28; radius:6
                color: (root.currentStatus===modelData)?root.hoverFill:(statusMouse.containsMouse?root.subtleFill:"transparent")
                border.width:1; border.color:(root.currentStatus===modelData)?root.faintFg:"transparent"
                Text { id:statusLabel; anchors.centerIn:parent; text:modelData.length?modelData:"Ej satt"; color:root.fg; font.pixelSize:10; font.bold:root.currentStatus===modelData }
                MouseArea { id:statusMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; enabled:root.configured&&!actionProcess.running; onClicked:root.setStatus(modelData) }
              }
            }
          }
          Row {
            width:parent.width; height:26; spacing:5
            Text { width:54; anchors.verticalCenter:parent.verticalCenter; text:root.tempUntil>0?("TILL "+root.tempUntilText()):"GILTIG:"; color:root.mutedFg; font.bold:true; font.pixelSize:9 }
            Repeater { model:[{"label":"Tills vidare","m":0},{"label":"30 min","m":30},{"label":"1 h","m":60},{"label":"2 h","m":120}]
              delegate: Rectangle { required property var modelData; width:tempLabel.implicitWidth+16; height:24; radius:6; color:root.tempMinutes===modelData.m?root.hoverFill:(tempMouse.containsMouse?root.subtleFill:"transparent"); border.width:1; border.color:root.tempMinutes===modelData.m?root.faintFg:"transparent"
                Text { id:tempLabel; anchors.centerIn:parent; text:modelData.label; color:root.fg; font.pixelSize:9 }
                MouseArea { id:tempMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; onClicked:root.tempMinutes=modelData.m }
              }
            }
            Rectangle { visible:root.tempUntil>0; width:52; height:24; radius:6; color:cancelTempMouse.containsMouse?root.hoverFill:root.subtleFill
              Text { anchors.centerIn:parent; text:"Avbryt"; color:root.fg; font.pixelSize:9 }
              MouseArea { id:cancelTempMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; enabled:!actionProcess.running; onClicked:root.cancelTemp() }
            }
          }
          Row {
            width:parent.width; height:32; spacing:6
            Rectangle { width:parent.width-142; height:32; radius:6; color:root.subtleFill
              TextInput { id:detailInput; anchors.fill:parent; anchors.margins:8; color:root.fg; selectionColor:root.accent; font.pixelSize:10; clip:true; maximumLength:120; verticalAlignment:TextInput.AlignVCenter; Keys.onReturnPressed:root.saveDetail() }
              Text { anchors.fill:parent; anchors.margins:8; text:"Valfri detalj, t.ex. n.rudolfsson.net"; color:root.mutedFg; font.pixelSize:10; visible:!detailInput.text.length&&!detailInput.activeFocus; verticalAlignment:Text.AlignVCenter }
            }
            Rectangle { width:64; height:32; radius:6; color:clearDetailMouse.containsMouse?root.hoverFill:root.subtleFill; opacity:(detailInput.text.length||root.currentDetail.length)?1:.45
              Text { anchors.centerIn:parent; text:"Rensa"; color:root.fg; font.pixelSize:10 }
              MouseArea { id:clearDetailMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; enabled:root.configured&&!actionProcess.running&&(detailInput.text.length>0||root.currentDetail.length>0); onClicked:root.clearDetail() }
            }
            Rectangle { width:66; height:32; radius:6; color:saveMouse.containsMouse?root.hoverFill:root.subtleFill
              Text { anchors.centerIn:parent; text:"Spara"; color:root.fg; font.pixelSize:10; font.bold:true }
              MouseArea { id:saveMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; enabled:root.configured&&!actionProcess.running; onClicked:root.saveDetail() }
            }
          }

          Rectangle { width:parent.width; height:1; color:root.faintFg }
          Column {
            width:parent.width; spacing:6
            Text { text:"NÄRVARO"; color:root.mutedFg; font.bold:true; font.pixelSize:10 }
            Text { text:(root.online ? "● Online" : "○ Offline") + "  ·  Läge: " + (root.presenceMode==="unknown" ? "okänt" : root.presenceMode.toUpperCase()); color:root.fg; font.pixelSize:11; font.bold:true }
            Text { text:root.lastSeen.length ? "Senaste kontakt: " + root.lastSeen : "Servern styr nattläge 23:30–04:00 och tvåtimmarsgränsen"; color:root.mutedFg; font.pixelSize:9 }
            Row {
              spacing:8
              Repeater {
                model:[{"label":"Auto","mode":"auto"},{"label":"Online","mode":"online"},{"label":"Offline","mode":"offline"}]
                delegate: Rectangle {
                  required property var modelData
                  width:92; height:30; radius:6
                  color:root.presenceMode===modelData.mode?root.hoverFill:(modeMouse.containsMouse?root.subtleFill:"transparent")
                  border.width:1; border.color:root.presenceMode===modelData.mode?root.fg:root.faintFg
                  Text { anchors.centerIn:parent; text:modelData.label; color:root.fg; font.pixelSize:10; font.bold:root.presenceMode===modelData.mode }
                  MouseArea { id:modeMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; enabled:root.configured&&!actionProcess.running; onClicked:root.setPresenceMode(modelData.mode) }
                }
              }
            }
          }

          Rectangle { width:parent.width; height:1; color:root.faintFg }
          Row {
            width:parent.width; height:60; spacing:8
            Column { width:parent.width-116; spacing:2
              Text { text:"NOW PLAYING"; color:root.mutedFg; font.bold:true; font.pixelSize:10 }
              Text { width:parent.width; text:!root.playerAvailable?(root.playerReason.length?root.playerReason:"Now Playing ej tillgängligt"):(root.playerPlaying?(root.playerArtist.length?root.playerArtist:"Spelar"):"Inget spelas just nu"); color:root.fg; font.pixelSize:11; font.bold:true; elide:Text.ElideRight }
              Text { width:parent.width; text:root.playerPlaying?((root.playerTitle||"Okänd titel")+(root.playerSource.length?" · "+root.playerSource:"")+(root.shareMusic?" · delas publikt":" · endast lokalt")):(root.shareMusic?"Delning är på":"Delning är av"); color:root.mutedFg; font.pixelSize:9; elide:Text.ElideRight }
            }
            Rectangle { width:108; height:32; anchors.verticalCenter:parent.verticalCenter; radius:6; color:musicMouse.containsMouse?root.hoverFill:root.subtleFill
              Text { anchors.centerIn:parent; text:root.shareMusic?"Delning PÅ":"Delning AV"; color:root.fg; font.pixelSize:10; font.bold:true }
              MouseArea { id:musicMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; enabled:root.configured&&!actionProcess.running; onClicked:root.toggleMusic() }
            }
          }

          Rectangle { width:parent.width; height:1; color:root.faintFg }
          Item { width:parent.width; height:18
            Text { anchors.left:parent.left; anchors.verticalCenter:parent.verticalCenter; text:"MICROLOG"; color:root.mutedFg; font.bold:true; font.pixelSize:10 }
            Text { id:microCount; anchors.right:parent.right; anchors.verticalCenter:parent.verticalCenter; text:microInput.text.length+" / 1000"; color:microInput.text.length>1000?root.fg:root.mutedFg; font.pixelSize:9 }
          }
          Rectangle {
            width:parent.width; height:80; radius:6; color:root.subtleFill
            TextEdit { id:microInput; anchors.fill:parent; anchors.margins:9; color:root.fg; selectionColor:root.accent; font.pixelSize:11; wrapMode:TextEdit.Wrap; clip:true; onTextChanged: { if(root.draftLoaded) draftTimer.restart() }
              Keys.onPressed: function(event){ if((event.modifiers & Qt.ControlModifier) && (event.key===Qt.Key_Return || event.key===Qt.Key_Enter)){root.publishMicrolog();event.accepted=true} }
            }
            Text { anchors.fill:parent; anchors.margins:9; text:"En kort tanke eller reflektion…"; color:root.mutedFg; font.pixelSize:11; visible:!microInput.text.length&&!microInput.activeFocus }
          }
          Row {
            width:parent.width; height:32; spacing:6
            Text { id:microFeedback; width:parent.width-196; anchors.verticalCenter:parent.verticalCenter; color:root.mutedFg; font.pixelSize:9; text:"" }
            Rectangle { width:66; height:32; radius:6; color:microClearMouse.containsMouse?root.hoverFill:root.subtleFill; opacity:microInput.text.length?1:.45
              Text { anchors.centerIn:parent; text:"Rensa"; color:root.fg; font.pixelSize:10 }
              MouseArea { id:microClearMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; enabled:microInput.text.length>0&&!microProcess.running; onClicked:root.clearMicro() }
            }
            Rectangle { width:118; height:32; radius:6; color:publishMouse.containsMouse?root.hoverFill:root.subtleFill; opacity:(microInput.text.trim().length>0&&microInput.text.length<=1000)?1:.45
              Text { anchors.centerIn:parent; text:microProcess.running?"Publicerar…":"Publicera"; color:root.fg; font.pixelSize:10; font.bold:true }
              MouseArea { id:publishMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; enabled:root.configured&&!microProcess.running&&microInput.text.trim().length>0&&microInput.text.length<=1000; onClicked:root.publishMicrolog() }
            }
          }
          Text { width:parent.width; text:"Ctrl+Enter publicerar · R uppdaterar · A Auto · O Online · F Offline · M musik · / detalj"; color:root.mutedFg; font.pixelSize:9; horizontalAlignment:Text.AlignHCenter }
        }
      }
    }
  }
  Component.onCompleted: refresh()
}
