var version

//Function to get parameters URL
$.urlParam = function(name){
    var results = new RegExp('[\?&]' + name + '=([^&#]*)').exec(window.location.href);
    if (results==null) {
       return null;
    }
    return decodeURI(results[1]) || 0;
}

//Function open page 
function openPage(page) {
  $.get(page+".html",function(data) {
    $('#content').html(data);
  });
}

//Function to open tab in pages
function openTab(evt, tabName) {
    var i, x, tablinks;
    x = document.getElementsByClassName("tab");
    for (i = 0; i < x.length; i++) {
      x[i].style.display = "none";
    }
    tablinks = document.getElementsByClassName("tablink");
    for (i = 0; i < x.length; i++) {
      tablinks[i].className = tablinks[i].className.replace(" w3-border-theme", "");
    }
    document.getElementById(tabName).style.display = "block";
    evt.currentTarget.firstElementChild.className += " w3-border-theme";
  }

//Function show/hide accordion
function accordion() {
  var acc = document.getElementsByClassName("accordion");
  var i;
  
  for (i = 0; i < acc.length; i++) {
    acc[i].addEventListener("click", function() {
      this.classList.toggle("active");
      var panel = this.nextElementSibling;
      if (panel.style.maxHeight) {
        panel.style.maxHeight = null;
      } else {
        panel.style.maxHeight = panel.scrollHeight + "px";
      } 
    });
  }
}


function checkSDCard() {
  $.get("cgi-bin/ui_sdcard.cgi", {cmd: "check_sdcard"}, function (result) {
    if ( result == "nok") {
      $('#notifAlarm').attr('style','color:red');
      $('#notifContent').html("<p></p>Your sdcard is mounted read-only. Settings can't be saved. \
      <br><p>Please try rebooting. If the problem persists, please <a target='_blank' href='https://github.com/EliasKotlyar/Xiaomi-Dafang-Hacks/search?q=read+only+sdcard&type=Issues'> \
      search for possible solutions.</a></p>");
    }
  });
}

// SD card mode (read-only / read-write) badge and modal.
// p1 = system partition (firmware, settings), p2 = data partition (logs, recordings),
// present only on cards made with the two partition layout.
var sdState = {};
var sdParts = {
  1: {name: "System", desc: "firmware and settings"},
  2: {name: "Data", desc: "recordings and timelapse"}
};
var sdReasons = {
  config: "read-only mode is enabled",
  fs_error: "the kernel found file system errors: repair the card (chkdsk / fsck on a PC) before writing to it",
  unknown: "mounted read-only for another reason"
};

function loadSdStatus() {
  $.get("cgi-bin/ui_sdcard.cgi", {cmd: "sdcard_status"}, function (result) {
    sdState = {};
    result.split("\n").forEach(function (line) {
      var f = line.split("#:#");
      if (f.length == 2) sdState[f[0]] = f[1];
    });
    var hasData = (sdState.p2_present == "true" && sdState.p2_mount != "none");
    var parts = hasData ? [1, 2] : [1];
    var anyError = false, anyRo = false, label = [];
    $('#sdParts').empty();
    parts.forEach(function (p) {
      var mount = sdState["p" + p + "_mount"], config = sdState["p" + p + "_config"],
          reason = sdState["p" + p + "_reason"], ro = (mount == "ro");
      if (reason == "fs_error") anyError = true;
      if (ro) anyRo = true;
      label.push((hasData ? sdParts[p].name.toLowerCase() + " " : "") + (ro ? "ro" : "rw"));
      var block = $('<div class="w3-panel w3-border w3-round"></div>');
      block.append($('<h4></h4>').text(sdParts[p].name + " partition (" + sdParts[p].desc + ")"));
      block.append($('<p></p>').html("Now: <b>" + (ro ? "read-only" : "writable") + "</b>" +
        (ro && sdReasons[reason] ? " (" + sdReasons[reason] + ")" : "") +
        ". At boot: <b>" + (config == "true" ? "read-only" : "writable") + "</b>."));
      var btnNow = $('<button class="w3-btn w3-border w3-margin-right w3-margin-bottom"></button>')
        .text(ro ? "Writable until reboot" : "Read-only until reboot")
        .prop('disabled', ro && reason == "fs_error")
        .on('click', function () { sdRemount(p, ro ? "rw" : "ro"); });
      var btnBoot = $('<button class="w3-btn w3-theme w3-margin-bottom"></button>')
        .text(config == "true" ? "Writable now and at boot" : "Read-only now and at boot")
        .prop('disabled', reason == "fs_error")
        .on('click', function () { sdConfig(p, config != "true"); });
      block.append($('<p></p>').append(btnNow).append(btnBoot));
      $('#sdParts').append(block);
    });
    $('#sdStatusText').text("SD: " + label.join(" · "))
      .removeClass("w3-red w3-orange w3-green")
      .addClass(anyError ? "w3-red" : (anyRo ? "w3-orange" : "w3-green"));
  });
}

function openSdModal() {
  $('#sdModalResult').text("");
  loadSdStatus();
  document.getElementById('sdModal').style.display = 'block';
}

function sdConfig(part, readonly) {
  if (readonly && !confirm("Make the " + sdParts[part].name.toLowerCase() +
      " partition read-only now and at boot? Nothing can be saved on it meanwhile."))
    return;
  $('#sdModalResult').text("Applying...");
  $.get("cgi-bin/ui_sdcard.cgi", {cmd: "sdcard_config", part: part, readonly: readonly ? "true" : "false"}, function (result) {
    $('#sdModalResult').text(result);
    loadSdStatus();
  });
}

function sdRemount(part, mode) {
  $('#sdModalResult').text("Applying...");
  $.get("cgi-bin/ui_sdcard.cgi", {cmd: "sdcard_remount", part: part, mode: mode}, function (result) {
    $('#sdModalResult').text(result);
    loadSdStatus();
  });
}

$(document).ready(function () {
  
    // Set git version to bottom page
    $.get("cgi-bin/state.cgi", {cmd: "version"}, function(version){document.getElementById("version").innerHTML = version;});

    // Check SD Card
    checkSDCard();
    loadSdStatus();

    // Display content depend url parameter
    if ( $.urlParam('url') != null )
        var url = $.urlParam('url')+".html"
    else
        var url = "live.html"

    //Check if theme configured
    var css = localStorage.getItem('theme')
    if ( css == null )
      css = "w3-theme-teal";
    //Select theme for theme modal
    $('#theme  option[value="'+css+'"]').prop("selected", true);
    // Set theme when changed in theme modal
    $('#theme').change(function () {
      var optionSelected = $(this).find("option:selected");
      localStorage.setItem("theme", optionSelected.val());
      location.reload();
    });
    
    $("#content").load(url);

});


