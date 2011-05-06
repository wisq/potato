var stat_timeout = null;
var ifaces = new Array();
var insanity_interval = null;
var any_down;

function getData() {
	$.getJSON('/stat.js', function(data) {
		updateStatus(data['status']);

		any_down = false;
		$.each(data['ifaces'], updateIF);
		setInsanity(!any_down);
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

function updateStatus(stat) {
	$('#ip-local' ).text(stat['ip_local' ] || 'unknown');
	$('#ip-remote').text(stat['ip_remote'] || 'unknown');
}

function updateIF(iface, mode) {
	var id = createIF(iface);

	if (mode == "down") { any_down = true; }

	ifaces[iface] = mode;
	$('#' + id + ' .i_mode').text(mode);
	$('#' + id + ' .i_image').removeClass().addClass('i_image mode_' + mode);
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
	}
	return id;
}

function toggleLink(iface) {
	reloadDataIn(1000);

	var mode = ifaces[iface];
	var new_mode = (mode == 'down') ? 'up' : 'down';

	updateIF(iface, 'busy');
	$.getJSON('/set/' + iface + '/' + new_mode, function(data) {
		if (data != 'SUCCESS') {
			alert(data);
		}
	});
}

function setInsanity(on) {
	if (insanity_interval != null) {
	}

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

$(document).ready(function() {
	reloadData();
});
