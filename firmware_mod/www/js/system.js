//Function save config
function saveConfig() {
    //Open modal window
    document.getElementById('save_confirm').style.display='block'

    var postData = { cmd: "save_config",
                     hostname: $('#hostname').val(),
                     password: $('#password').val(),
                     timezone: $('#timezone').children("option:selected").val(),
                     github_token: $('#github_token').val(),
                     ap_ssid: $('#ap_ssid').val(),
                     ap_password: $('#ap_password').val(),
                     connect_timeout: $('#connect_timeout').val(),
                     ap_timeout: $('#ap_timeout').val(),
                     usb_eth: $('#usb_eth').is(":checked") ? 'on' : 'off',
                     ssh_port: $('#ssh_port').val(),
                     ssh_key: $('#ssh_key').val().replace(/ /g,'%20'),
                     ssh_password: $('#ssh_password').is(":checked") ? 'on' : 'off',
                     ntp: $('#ntp').val()};

    $.post("cgi-bin/ui_system.cgi",postData,function(result){
        //Open modal window
        if ( result != "")
            $('#save_result').html(result);
        else
            $('#save_result').html("Nothing to update");
        if (wifiNetworksChanged)
            saveWifiNetworks();
    });


}

//Function get config
function getConfig() {
    // get config and put to hmtl elements
    $.get("cgi-bin/ui_system.cgi", {cmd: "get_config"}, function(config){
        var config_all = config.split("\n");
        for (var i = 0; i < config_all.length-1; i++) {
         var config_info = config_all[i].split("#:#");
         if ( config_info[0] == "timezone" || config_info[0] == "currenttime")
            $('#'+config_info[0]).html(config_info[1]);
         else if (config_info[0] === "usb_eth")
            $('#'+config_info[0]).prop('checked', config_info[1] === 'on');
         else if (config_info[0] === "ssh_password")
            $('#'+config_info[0]).prop('checked', config_info[1] === 'on');
         else
            $('#'+config_info[0]).attr("value",config_info[1]);

       }
    });

}

// Wifi networks list
var wifiNetworksChanged = false;

// Like encodeURIComponent, but also escapes !'()* (func.cgi evals the values)
function cgiEncode(value) {
    return encodeURIComponent(value).replace(/[!'()*]/g, function (c) {
        return '%' + c.charCodeAt(0).toString(16).toUpperCase();
    });
}

function addWifiNetwork(ssid, priority, hidden, secured, index) {
    var isNew = (ssid === undefined);
    var row = $('<tr>\
        <td><input class="w3-input net-ssid" type="text" maxlength="32"></td>\
        <td><input class="w3-input net-pass" type="password" autocomplete="new-password"></td>\
        <td><input class="w3-input net-prio" type="number" min="0" max="999" style="width:5em"></td>\
        <td><input class="w3-check net-hidden" type="checkbox"></td>\
        <td><button type="button" class="w3-btn w3-small w3-red">Remove</button></td></tr>');
    row.find('.net-ssid').val(isNew ? '' : ssid);
    row.find('.net-prio').val(isNew ? 0 : priority);
    row.find('.net-hidden').prop('checked', hidden === true);
    row.find('.net-pass').attr('placeholder', isNew ? '' : (secured ? 'unchanged' : 'open network'));
    // Position in the saved list, used to keep the current password when it is left empty
    row.data('orig', isNew ? '' : index);
    row.find('input').on('input change', function () { wifiNetworksChanged = true; });
    row.find('button').on('click', function () { row.remove(); wifiNetworksChanged = true; });
    $('#wifi_networks tbody').append(row);
    if (isNew) wifiNetworksChanged = true;
}

function getWifiNetworks() {
    $('#wifi_networks tbody').empty();
    $.get("cgi-bin/ui_system.cgi", {cmd: "get_wifi_networks"}, function (data) {
        var lines = data.split("\n");
        var index = 0;
        for (var i = 0; i < lines.length; i++) {
            if (lines[i] === "") continue;
            var f = lines[i].split("#:#");
            index++;
            addWifiNetwork(f[0], parseInt(f[1], 10) || 0, f[2] === "true", f[3] === "true", index);
        }
        wifiNetworksChanged = false;
    });
}

function saveWifiNetworks() {
    var body = "cmd=save_wifi_networks";
    var rows = $('#wifi_networks tbody tr');
    rows.each(function (i) {
        var row = $(this);
        body += "&net_ssid_" + i + "=" + cgiEncode(row.find('.net-ssid').val());
        body += "&net_pass_" + i + "=" + cgiEncode(row.find('.net-pass').val());
        body += "&net_prio_" + i + "=" + cgiEncode(row.find('.net-prio').val());
        body += "&net_hidden_" + i + "=" + (row.find('.net-hidden').is(':checked') ? 'true' : 'false');
        body += "&net_orig_" + i + "=" + row.data('orig');
    });
    body += "&net_count=" + rows.length;
    $.ajax({url: "cgi-bin/ui_system.cgi", type: "POST", data: body,
            contentType: "application/x-www-form-urlencoded", processData: false})
        .done(function (result) {
            $('#save_result').append(result);
            getWifiNetworks();
        });
}

//Function loaded when script load
function onLoad() {
    //Activate accordion
    accordion();
    getConfig();
    getWifiNetworks();
}

//Main program
onLoad();
