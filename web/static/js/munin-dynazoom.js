var GRAPH_TOP = 33,
	GRAPH_PADDING_LEFT = 66,
	GRAPH_PADDING_RIGHT = 26;
var DEFAULT_DATE = '2015-01-01T00:00:00+0100';

// Define vars
var scale;
var clickCounter;
var initial_left;
var initial_top;
var qs = new Querystring();

// UI
var form;
var image;
var divOverlay;
var f_plugin_name, f_start_epoch, f_stop_epoch, f_start_iso8601, f_stop_iso8601,
	f_lower_limit, f_upper_limit, f_size_x, f_size_y, f_cgiurl_graph;

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
	'size_y': 400,
	'graph_ext': 'png'
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
	f_cgiurl_graph = $('#cgiurl_graph');
	f_graph_ext = $('#graph_ext');
	form = $('#myNewForm');
	image = $('#image');
	divOverlay = $('#overlayDiv');

	// Insert values in the form
	f_cgiurl_graph.val(getParam("cgiurl_graph"));
	f_plugin_name.val(getParam("plugin_name"));
	f_start_epoch.val(getParam("start_epoch"));
	f_stop_epoch.val(getParam("stop_epoch"));
	f_lower_limit.val(getParam("lower_limit"));
	f_upper_limit.val(getParam("upper_limit"));
	f_size_x.val(getParam("size_x"));
	f_size_y.val(getParam("size_y"));
	f_graph_ext.val(getParam("graph_ext"));

	start_epoch = parseInt(f_start_epoch.val());
	stop_epoch = parseInt(f_stop_epoch.val());

	// Define listeners
	$('#btnMaj').click(majDates);
	$('#btnZoomOut').click(zoomOut);
	$('#reset').click(reset);

	updateStartStop();

	// Restrict image width (SVG graph expands inappropriately)
	image.css('width', (GRAPH_PADDING_LEFT + GRAPH_PADDING_RIGHT + parseInt(f_size_x.val())) + 'px');

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
	var urlPrefix = f_cgiurl_graph.val() + (f_cgiurl_graph.val() != '/' ? '/' : '');

	var url = urlPrefix + f_plugin_name.val()
		+ "-pinpoint=" + parseInt(f_start_epoch.val()) + "," + parseInt(f_stop_epoch.val())
		+ "." + f_graph_ext.val()
		+ "?size_x=" + f_size_x.val()
		+ "&size_y=" + f_size_y.val();

	if (f_lower_limit.val())
		url += "&lower_limit=" + f_lower_limit.val();

	if (f_upper_limit.val())
		url += "&upper_limit=" + f_upper_limit.val();

	image.attr('src', url);

	return ((parseInt(f_stop_epoch.val()) - parseInt(f_start_epoch.val())) / parseInt(f_size_x.val()));
}

function updateStartStop() {
	f_start_iso8601.val(new Date(f_start_epoch.val() * 1000).formatDate(Date.DATE_ISO8601));
	f_stop_iso8601.val(new Date(f_stop_epoch.val() * 1000).formatDate(Date.DATE_ISO8601));
}

function divMouseMove(mouseMoveEvent) {
	var delta_x,
		size_x,
		mouseX = mouseMoveEvent.pageX;

	// Mouse outside of the graph
	if (mouseX < getLeftOffset() + GRAPH_PADDING_LEFT)
		mouseX = getLeftOffset() + GRAPH_PADDING_LEFT;
	if (mouseX > getLeftOffset() + image.width() - GRAPH_PADDING_RIGHT)
		mouseX = getLeftOffset() + image.width() - GRAPH_PADDING_RIGHT;

	// Handling the borders (X1>X2 ou X1<X2)
	var current_width = mouseX - initial_left - getLeftOffset();
	if (current_width < 0) {
		divOverlay.css('left', mouseX - getLeftOffset());
		delta_x = mouseX - GRAPH_PADDING_LEFT - getLeftOffset();
		size_x = -current_width;
		divOverlay.css('width', size_x);
	} else {
		divOverlay.css('left', initial_left);
		delta_x = initial_left - GRAPH_PADDING_LEFT;
		size_x = current_width;
		divOverlay.css('width', size_x);
	}

	// Compute the UNIX epochs (only for horizontal)
	f_start_epoch.val((start_epoch + scale * delta_x).toFixed());
	f_stop_epoch.val((start_epoch + scale * (delta_x + size_x)).toFixed());

	// update !
	updateStartStop();
}

function startZoom(mouseMoveEvent) {
	var leftOffset = getLeftOffset();

	if (mouseMoveEvent.pageX < leftOffset + GRAPH_PADDING_LEFT
			|| mouseMoveEvent.pageX > leftOffset + image.width() - GRAPH_PADDING_RIGHT) {
		clickCounter--;
		return;
	}

	initial_left = mouseMoveEvent.pageX - leftOffset;
	initial_top = mouseMoveEvent.pageY;

	// Fixed, since zoom is only horizontal
	var top = image.css('top') == 'auto' ? GRAPH_TOP : (parseInt(image.css('top').replace("px", "")) + GRAPH_TOP);
	divOverlay.css('top', top + "px");
	divOverlay.css('height', parseInt(f_size_y.val()) + 1);

	// Show the div
	divOverlay.css('visibility', 'visible');
	divOverlay.addClass('dragging');

	// Initial show
	divOverlay.css('left', mouseMoveEvent.pageX - leftOffset);
	//divOverlay.style.width = (+form.size_x.value) / 4;
	divOverlay.css('width', 0);

	// Set events
	image.mousemove(divMouseMove);
	divOverlay.mousemove(divMouseMove);
	divOverlay.click(click);
}

function endZoom() {
	divOverlay.removeClass('dragging');
	divOverlay.addClass('dragged');

	// Remove mousemove events
	image.unbind('mousemove');
	divOverlay.unbind('mousemove');
	divOverlay.unbind('click');
	divOverlay.click(doZoom);
}

function clearZoom() {
	divOverlay.css('visibility', 'hidden');
	divOverlay.css('width', '0');
	divOverlay.removeClass('dragged');
	divOverlay.unbind('click');

	// reset the zoom
	f_start_epoch.val(start_epoch);
	f_stop_epoch.val(stop_epoch);

	updateStartStop();
}

function doZoom() {
	scale = refreshImg();
	start_epoch = parseInt(f_start_epoch.val());
	stop_epoch = parseInt(f_stop_epoch.val());
	clickCounter++;
	divOverlay.css('visibility', 'hidden');
	divOverlay.css('width', '0');
	divOverlay.removeClass('dragged');
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
