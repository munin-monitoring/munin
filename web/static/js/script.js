/**
 * Main UI script
 *  This file is included in every page
 */

$(document).ready(function() {
	// Navigation toggle on tablets
	$('#navToggle').click(function() {
		var nav = $('#nav');

		if ($(this).hasClass('expanded')) {
			$(this).removeClass('expanded');
			nav.hide();
		} else {
			$(this).addClass('expanded');
			nav.show();
		}
	});

	// Init toolbar component
	window.toolbar = $('header').toolbar();

	// Prepare settings modal
	var settingsModalWrap = $('#settingsModalWrap');
	settingsModalWrap.find('settings_save').click(function() {
		setCookie('graphs_format', $('#graphsFormat').val(), 1000);
	});

	var settingsModal = new Modal('settings', settingsModalWrap);
	settingsModal.setTitle('Settings');

	window.toolbar.addActionIcon('mdi-settings', 'Settings', true, function() {
		settingsModal.show();
	});
});


/**
 * Saves a var in URL
 * @param key
 * @param val
 */
function saveState(key, val) {
	// Check if history.pushState is supported by user's browser
	if (!history.pushState)
		return;

	// Encode key=val in URL
	var qs = new Querystring();
	qs.set(key, val);

	// Replace URL
	var url = $.param(qs.params);
	var pageName = $(document).find('title').text();
	window.history.replaceState('', pageName, '?' + url);
}

/**
 * Creates a cookie
 * Source: http://www.w3schools.com/js/js_cookies.asp
 */
function setCookie(cname, cvalue, exdays) {
	var d = new Date();
	d.setTime(d.getTime() + (exdays*24*60*60*1000));
	var expires = "expires="+d.toUTCString();
	document.cookie = cname + "=" + cvalue + "; " + expires;
}

/**
 * Get a cookie
 * Source: http://www.w3schools.com/js/js_cookies.asp
 */
function getCookie(cname) {
	var name = cname + "=";
	var ca = document.cookie.split(';');
	for(var i=0; i<ca.length; i++) {
		var c = ca[i];
		while (c.charAt(0)==' ') c = c.substring(1);
		if (c.indexOf(name) == 0) return c.substring(name.length,c.length);
	}
	return "";
}
