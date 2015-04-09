var Y_AXIS_POSX = 66;
var GRAPH_TOP = 33;
var DEFAULT_DATE = '2015-01-01T00:00:00+0100';

// Define vars
var scale;
var clickCounter;
var initial_left;
var initial_top;
var cgiurl_graph;
var qs = new Querystring();

// UI
var form;
var image;
var divOverlay;
var f_plugin_name, f_start_epoch, f_stop_epoch, f_start_iso8601, f_stop_iso8601,
	f_lower_limit, f_upper_limit, f_size_x, f_size_y;

// Form params
var start_epoch;
var stop_epoch;

// Form default values
var timestamp = Math.round(new Date().getTime()/1000);
var defaultValues = {
	'cgiurl_graph': '/munin-cgi/munin-cgi-graph',
	'plugin_name': 'localdomain/localhost.localdomain/if_eth0',
	'start_epoch': timestamp - 1000000,
	'stop_epoch': timestamp,
	'lower_limit': '',
	'upper_limit': '',
	'size_x': 800,
	'size_y': 400
};

$(document).ready(function() {
	// Define global vars
	f_plugin_name = $('#plugin_name');
	f_start_epoch = $('#start_epoch');
	f_stop_epoch = $('#stop_epoch');
	f_start_iso8601 = $('#start_iso8601');
	f_stop_iso8601 = $('#stop_iso8601');
	f_lower_limit = $('#lower_limit');
	f_upper_limit = $('#upper_limit');
	f_size_x = $('#size_x');
	f_size_y = $('#size_y');
	form = $('#myNewForm');
	image = $('#image');
	divOverlay = $('#overlayDiv');

	// Insert values in the form
	cgiurl_graph = getParam("cgiurl_graph");
	f_plugin_name.val(getParam("plugin_name"));
	f_start_epoch.val(getParam("start_epoch"));
	f_stop_epoch.val(getParam("stop_epoch"));
	f_lower_limit.val(getParam("lower_limit"));
	f_upper_limit.val(getParam("upper_limit"));
	f_size_x.val(getParam("size_x"));
	f_size_y.val(getParam("size_y"));

	start_epoch = parseInt(f_start_epoch.val());
	stop_epoch = parseInt(f_stop_epoch.val());

	// Define listeners
	$('#btnMaj').click(majDates);
	$('#btnZoomOut').click(zoomOut);
	$('#reset').click(reset);

	updateStartStop();

	// Refresh the image with the selected params
	scale = refreshImg();

	// Sets onClick handlers
	divOverlay.click(doZoom);
	image.click(click);
	clickCounter = 1;

	$(document).keyup(function(e) {
		if (e.keyCode == 27) {
			if (clickCounter % 3 == 0) {
				clickCounter++;
				clearZoom();
			}
		}
	});

	$('#formatExample').text(new Date().formatDate(Date.DATE_ISO8601));
});

function getParam(paramName) {
	return qs.get(paramName, defaultValues[paramName]);
}

function refreshImg() {
	var urlPrefix = cgiurl_graph + (cgiurl_graph != '/' ? '/' : '');

	image.attr('src', urlPrefix + f_plugin_name.val()
			+ "-pinpoint=" + parseInt(f_start_epoch.val()) + "," + parseInt(f_stop_epoch.val())
			+ ".png"
			+ "?lower_limit=" + f_lower_limit.val()
			+ "&upper_limit=" + f_upper_limit.val()
			+ "&size_x=" + f_size_x.val()
			+ "&size_y=" + f_size_y.val());

	return ((parseInt(f_stop_epoch.val()) - parseInt(f_start_epoch.val())) / parseInt(f_size_x.val()));
}

function updateStartStop() {
	f_start_iso8601.val(new Date(f_start_epoch.val() * 1000).formatDate(Date.DATE_ISO8601));
	f_stop_iso8601.val(new Date(f_stop_epoch.val() * 1000).formatDate(Date.DATE_ISO8601));
}

function divMouseMove(mouseMoveEvent) {
	var delta_x;
	var size_x;

	// Handling the borders (X1>X2 ou X1<X2)
	var current_width = mouseMoveEvent.pageX - initial_left - getLeftOffset();
	if (current_width < 0) {
		divOverlay.css('left', mouseMoveEvent.pageX - getLeftOffset());
		delta_x = mouseMoveEvent.pageX - Y_AXIS_POSX - getLeftOffset();
		size_x = -current_width;
		divOverlay.css('width', size_x);
	} else {
		divOverlay.css('left', initial_left);
		delta_x = initial_left - Y_AXIS_POSX;
		size_x = current_width;
		divOverlay.css('width', size_x);
	}

	// Compute the epochs UNIX (only for horizontal)
	f_start_epoch.val((start_epoch + scale * delta_x).toFixed());
	f_stop_epoch.val((start_epoch + scale * (delta_x + size_x)).toFixed());

	// update !
	updateStartStop();
}

function startZoom(mouseMoveEvent) {
	if (mouseMoveEvent.pageX - getLeftOffset() < Y_AXIS_POSX) {
		clickCounter--;
		return;
	}

	initial_left = mouseMoveEvent.pageX - getLeftOffset();
	initial_top = mouseMoveEvent.pageY;

	// Fixed, since zoom is only horizontal
	var top = image.css('top') == 'auto' ? GRAPH_TOP : (parseInt(image.css('top').replace("px", "")) + GRAPH_TOP);
	divOverlay.css('top', top + "px");
	divOverlay.css('height', parseInt(f_size_y.val()) + 1);

	// Show the div
	divOverlay.css('visibility', 'visible');
	divOverlay.addClass('overlayDiv_dragging');

	// Initial show
	divOverlay.css('left', mouseMoveEvent.pageX - getLeftOffset());
	//divOverlay.style.width = (+form.size_x.value) / 4;
	divOverlay.css('width', 0);

	// Set events
	image.mousemove(divMouseMove);
	divOverlay.mousemove(divMouseMove);
	divOverlay.click(click);
}

function endZoom() {
	divOverlay.removeClass('overlayDiv_dragging');
	divOverlay.addClass('overlayDiv_dragged');

	// Remove mousemove events
	image.unbind('mousemove');
	divOverlay.unbind('mousemove');
	divOverlay.unbind('click');
	divOverlay.click(doZoom);
}

function clearZoom() {
	divOverlay.css('visibility', 'hidden');
	divOverlay.css('width', '0');
	divOverlay.removeClass('overlayDiv_dragged');
	divOverlay.unbind('click');

	// reset the zoom
	f_start_epoch.val(start_epoch);
	f_stop_epoch.val(stop_epoch);

	updateStartStop();
}

function doZoom() {
	refreshImg();
	clickCounter++;
	divOverlay.css('visibility', 'hidden');
	divOverlay.css('width', '0');
	divOverlay.removeClass('overlayDiv_dragged');
	divOverlay.unbind('click');
}

function zoomOut() {
	f_start_epoch.val(start_epoch - scale * f_size_x.val());
	f_stop_epoch.val(stop_epoch - scale * f_size_y.val());
	form.submit();
}

function fillDate(date, default_date) {
	return date + default_date.substring(date.length, default_date.length);
}

function majDates() {
	var start_manual = fillDate(f_start_iso8601.val(), DEFAULT_DATE);
	var stop_manual = fillDate(f_stop_iso8601.val(), DEFAULT_DATE);

	var dateRegex = /(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2}).(\d{4})/;

	if (dateRegex.test(start_manual)) {
		var date_start_parsed = new Date(start_manual.replace(dateRegex, "$2 $3, $1 $4:$5:$6"));
		f_start_epoch.val(date_start_parsed.getTime() / 1000);
	}

	if (dateRegex.test(stop_manual)) {
		var date_stop_parsed = new Date(stop_manual.replace(dateRegex, "$2 $3, $1 $4:$5:$6"));
		f_stop_epoch.val(date_stop_parsed.getTime() / 1000);
	}

	form.submit();
}

/**
 * Returns image x position in page
 * We can't compute this once for all since it can change
 * 	during life cycle (when resizing window, navigation menu can be hidden)
 */
function getLeftOffset() {
	return image.parent().position().left;
}

/**
 * Click loop. Called on image click
 */
function click(event) {
	switch ((clickCounter++) % 3) {
		case 0:
			clearZoom();
			break;
		case 1:
			startZoom(event);
			break;
		case 2:
			endZoom();
			break;
		default: break;
	}
}

function reset() {
	f_start_epoch.val(getParam("start_epoch"));
	f_stop_epoch.val(qs.get("stop_epoch"));
	f_lower_limit.val(getParam("lower_limit"));
	f_upper_limit.val(getParam("upper_limit"));
	f_size_x.val(getParam("size_x"));
	f_size_y.val(getParam("size_y"));

	start_epoch = parseInt(f_start_epoch.val());
	stop_epoch = parseInt(f_stop_epoch.val());

	updateStartStop();
}
