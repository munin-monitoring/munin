// Insert values in the form
var qs = new Querystring();

var form = document.getElementById("myNewForm");
var image = document.getElementById("image");
var divOverlay = document.getElementById("overlayDiv");


form.plugin_name.value = qs.get("plugin_name", "localdomain/localhost.localdomain/if_eth0");
form.start_epoch.value = qs.get("start_epoch", "1236561663");
form.stop_epoch.value = qs.get("stop_epoch", "1237561663");
form.lower_limit.value = qs.get("lower_limit", "");
form.upper_limit.value = qs.get("upper_limit", "");
form.size_x.value = qs.get("size_x", "");
form.size_y.value = qs.get("size_y", "");

form.btnMaj.onclick = majDates;
form.btnZoomOut.onclick = zoomOut;

// Refresh the image with the selected params
var scale = refreshImg();

function refreshImg() {
	image.src = "/cgi-bin/munin-cgi-graph/"
		+ form.plugin_name.value 
		+ "-pinpoint=" + parseInt(form.start_epoch.value) + "," + parseInt(form.stop_epoch.value)
		+ ".png"
		+ "?" 
		+ "&lower_limit=" + form.lower_limit.value
		+ "&upper_limit=" + form.upper_limit.value
		+ "&size_x=" + form.size_x.value
		+ "&size_y=" + form.size_y.value
	;

	return ((+form.stop_epoch.value) - (+form.start_epoch.value)) / (+form.size_x.value);
}

var start_epoch = (+form.start_epoch.value);
var stop_epoch = (+form.stop_epoch.value);
var initial_left;
var initial_top;

updateStartStop();

function updateStartStop() {
	form.start_iso8601.value = new Date(form.start_epoch.value * 1000).formatDate(Date.DATE_ISO8601);
	form.stop_iso8601.value = new Date(form.stop_epoch.value * 1000).formatDate(Date.DATE_ISO8601);
}

function divMouseMove(mouseMouveEvent) {
	var delta_x;
	var size_x;

	// Handling the borders (X1>X2 ou X1<X2)
	var current_width = mouseMouveEvent.pageX - initial_left;
	if (current_width < 0) {
		divOverlay.style.left = mouseMouveEvent.pageX;
		delta_x = mouseMouveEvent.pageX - 63; // the Y Axis is 63px from the left border
		divOverlay.style.width = size_x = - current_width;
	} else {
		divOverlay.style.left = initial_left;
		delta_x = initial_left - 63; // the Y Axis is 63px from the left border
		divOverlay.style.width = size_x = current_width;
	}
	
	// Compute the epochs UNIX (only for horizontal)
	form.start_epoch.value = start_epoch + scale * delta_x;
	form.stop_epoch.value = start_epoch + scale * ( delta_x + size_x );
	
	// update !
	updateStartStop();
}

function startZoom(mouseMouveEvent) {
	initial_left = mouseMouveEvent.pageX;
	initial_top = mouseMouveEvent.pageY;
	
	// Fixed, since zoom is only horizontal
	divOverlay.style.top = image.style.top.replace("px", "") + 29;
	divOverlay.style.height = (+form.size_y.value) + 1;


	// Show the div
	divOverlay.style.visibility = 'visible';
	divOverlay.style.backgroundColor = '#555'; 

	// Initial show
	divOverlay.style.left = mouseMouveEvent.pageX;
	//divOverlay.style.width = (+form.size_x.value) / 4;
	divOverlay.style.width = 40;
	
	// Fix the handles
	image.onmousemove = divMouseMove;
	divOverlay.onmousemove = divMouseMove;
	divOverlay.onclick = image.onclick;

}

function endZoom(event) {
	divOverlay.style.backgroundColor = '#000'; 
	image.onmousemove = undefined;
	divOverlay.onmousemove = undefined;
	divOverlay.onclick = doZoom;
}

function clearZoom(event) {
	divOverlay.style.visibility = 'hidden';
	divOverlay.style.width = 0;
	
	// reset the zoom
	form.start_epoch.value = start_epoch;
	form.stop_epoch.value = stop_epoch;

	updateStartStop();
}

function doZoom(event) {
	// Navigate !
	form.submit();
}

function zoomOut(event) {
	form.start_epoch.value = start_epoch - scale * form.size_x.value;
	form.stop_epoch.value= stop_epoch + scale * form.size_y.value;
	form.submit();
}

function fillDate(date, default_date) {
	return date + default_date.substring(date.length, default_date.length);
}

function majDates(event) {
	var default_date = "2009-01-01T00:00:00+0100";

	var start_manual = fillDate(form.start_iso8601.value, default_date);
	var stop_manual = fillDate(form.stop_iso8601.value, default_date);
	
	var dateRegex = /(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2}).(\d{4})/;
	
	if (dateRegex.test(start_manual)) {
		var date_parsed = new Date(start_manual.replace(dateRegex, "$2 $3, $1 $4:$5:$6"));
		form.start_epoch.value = date_parsed.getTime() / 1000;
	}

	if (dateRegex.test(stop_manual)) {
		var date_parsed = new Date(stop_manual.replace(dateRegex, "$2 $3, $1 $4:$5:$6"));
		form.stop_epoch.value = date_parsed.getTime() / 1000;
	}

	form.submit();
}

// Sets the onClick handler
divOverlay.onclick = image.onclick = click;
var clickCounter = 1;
function click(event) {
	switch ((clickCounter++) % 3) {
		case 0: 
			clearZoom(event);
			break;
		case 1: 
			startZoom(event);
			break;
		case 2: 
			endZoom(event);
			break;			
	}
}
