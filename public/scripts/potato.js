var stat_timeout = null;
var ifaces = new Array();
var insanity_interval = null;
var any_down;
var checked_in = false;

function getData() {
	$.getJSON('stat.js', function(data) {
		any_down = false;
		$.each(data['ifaces'], updateIF);
		setInsanity(!any_down);

		$('#log_block .log').addClass('delete');
		$('#log_block .template').removeClass('delete');
		$.each(data['log'], updateLog);
		$('#log_block .delete').remove();
	});
}

function reloadData() {
	getData();
	reloadDataIn(3000);
}

function reloadDataIn(timeout) {
	clearTimeout(stat_timeout);
	stat_timeout = setTimeout(reloadData, timeout);
}

function updateIFmode(iface, mode) {
	var id = createIF(iface);

	if (mode == "down") { any_down = true; }

	ifaces[iface] = mode;
	$('#' + id + ' .i_mode').text(mode);
	$('#' + id + ' .i_image').removeClass().addClass('i_image mode_' + mode);

	return id;
}

function updateIF(iface, data) {
	var id = updateIFmode(iface, data['status']);

	$('#' + id + ' .i_ipdata .ip_local' ).text(data['ip_local']);
	$('#' + id + ' .i_ipdata .ip_remote').text(data['ip_remote']);

	$('#ip_local_'  + iface).text(data['ip_local']);
	$('#ip_remote_' + iface).text(data['ip_remote']);

	var pings = data['pings'];
	var ping_elems = $('#' + id + ' .i_pings .ping');
	for (i = 0; i < pings.length; i++) {
		var ping  = pings[i];
		var elem  = $(ping_elems[i]);
		var trend = 'ping_trend_' + ping['trend'];
		var icon  = $('#' + trend);

		elem.removeClass().addClass('ping ' + trend);
		elem.find('.icon').text(icon.text());
		elem.find('.percent').text(ping['percent']);
	}
}

function createIF(iface) {
	var id = 'c_' + iface;
	var container = $('#' + id);
	if (container.length < 1) {
		var template = $('#iface_template');
		container = template.clone().removeClass('template').attr('id', id);
		template.parent().append(container);
		$('#' + id + ' .i_name').text(iface);

		container.click(function(ev) { toggleLink(iface); });
		container.mouseenter(function(ev) { showAddrs(id, iface); });
		container.mouseleave(function(ev) { hideAddrs(); });
	}
	return id;
}

function toggleLink(iface) {
	if (!checked_in) {
		alert("Click the potato to log in first!\nWhen done, click again to log out.");
		return;
	}

	reloadDataIn(1000);

	var mode = ifaces[iface];
	var new_mode = (mode == 'down') ? 'up' : 'down';

	updateIFmode(iface, 'busy');
	$.get('admin/set/' + iface + '/' + new_mode, function(data) {
		if (data != 'SUCCESS') {
			alert(data);
		}
	});
}

function showAddrs(id, iface) {
	var ip_local  = $('#' + id + ' .i_ipdata .ip_local' ).text();
	var ip_remote = $('#' + id + ' .i_ipdata .ip_remote').text();

	$('#addrs .ip_local' ).attr('id', '#ip_local_'  + iface).text(ip_local);
	$('#addrs .ip_remote').attr('id', '#ip_remote_' + iface).text(ip_remote);

	$('#addrs').removeClass('invisible');
	$('#addrs').stop().fadeTo(200, 1);
}

function hideAddrs() {
	$('#addrs').stop().fadeTo(1000, 0.3);
}

function setInsanity(on) {
	if (on) {
		$('#insanity-off').hide();
		if (insanity_interval == null) {
			var insanity = $('#insanity-on');
			insanity_interval = setInterval(function() { insanity.toggle(); }, 250);
		}
	} else {
		clearInterval(insanity_interval);
		insanity_interval = null;
		$('#insanity-off').show();
		$('#insanity-on').hide();
	}
}

function updateLog(index, log) {
	var id = 'log_' + log['time'].toString().replace('.', '_');
	var found = $('#' + id);
	if (found.length >= 1) {
		found.removeClass('delete');
		return;
	}

	var template = $('#log_template');
	var container = template.clone().removeClass('template').attr('id', id);

	container.find('.l_user').text(log['user']);
	container.find('.l_iface').text(log['iface'] || '');
	container.find('.l_action').addClass('action_' + log['action']);

	template.parent().append(container);
}

function toggleCheckIn() {
	var url = checked_in ? 'admin/check/out' : 'admin/check/in';
	$.get(url, function(data) {
		if (data != 'SUCCESS') {
			alert(data);
		} else {
			checked_in = !checked_in;
			if (checked_in) {
				$('#checked-in').show();
				$('#checked-out').hide();
			} else {
				$('#checked-out').show();
				$('#checked-in').hide();
			}

			reloadData();
		}
	});

}

$(document).ready(function() {
	$('.checkin').click(function(ev) { toggleCheckIn(); });
	reloadData();
});
