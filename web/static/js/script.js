/**
 * Main UI script
 *  This file is included in every page
 */
window.isRetina = (
	window.devicePixelRatio > 1 ||
	(window.matchMedia && window.matchMedia("(-webkit-min-device-pixel-ratio: 1.5),(-moz-min-device-pixel-ratio: 1.5),(min-device-pixel-ratio: 1.5)").matches)
);

$(document).ready(function() {
	// Check if toolbar has been included (it is not on dynazoom modal)
	if (jQuery.fn.toolbar) {
		// Init toolbar component
		window.toolbar = $('header').toolbar();

		addSettingsActionIcon();
	}
});

/**
 * Adds a refresh action icon in toolbar
 */
function addRefreshActionIcon(autoRefresh) {
	// Add toolbar actions
	window.toolbar.addActionIcon('mdi-refresh', 'Refresh graphs', false, function() {
		autoRefresh.refreshAll();
	});
}

/**
 * Adds a settings action icon in toolbar
 */
function addSettingsActionIcon() {
	// Prepare settings modal
	var settingsModal = null;
	var settingsModalWrap = $('#settingsModalWrap');

	// Set settings values
	var graphExt_input = $('#graph_ext');
	var graphAutoRefresh_input = $('#graph_autoRefresh');

	var setSettingsValues = function() {
		graphExt_input.val(getCookie('graph_ext', 'png'));
		graphAutoRefresh_input.prop('checked', getCookie('graph_autoRefresh', 'true') == 'true');
	};
	setSettingsValues();

	settingsModalWrap.find('#settings_save').click(function() {
		// Save parameters
		var graphExt = graphExt_input.val();
		setCookie('graph_ext', graphExt);

		var graphAutoRefresh = graphAutoRefresh_input.prop('checked');
		setCookie('graph_autoRefresh', graphAutoRefresh);

		// Update UI
		$('#content').attr('data-graphext', graphExt);
		if (window.graphs !== undefined) {
			$.each(window.graphs, function (index, graph) {
				$(graph).data('graph').setGraphExt(graphExt);
			});
		}

		if (window.autoRefresh !== undefined) {
			if (graphAutoRefresh)
				window.autoRefresh.start();
			else
				window.autoRefresh.stop();
		}

		// Close modal
		settingsModal.hide();
	});

	// Cancel
	settingsModalWrap.find('#settings_cancel').click(function() {
		setSettingsValues();
		settingsModal.hide();
	});

	settingsModal = new Modal('settings', settingsModalWrap, {
		size: 'small',
		title: 'Settings'
	});

	window.toolbar.addActionIcon('mdi-settings', 'Settings', true, function() {
		settingsModal.show();
	});
}

function removeTabIndexOutline() {
	// Enable outline on elements only if browser DOM using <Tab> key
	$('[tabindex]').focus(function() {
		$(this).css('outline', 'none');
	}).on('keyup', function (event) {
		if(event.keyCode == 9)
			$(this).css('outline', '');
	});
}

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
 * Returns an array of the parameters sitting in the URL
 * 	Source: http://stackoverflow.com/posts/2880929/revisions
 */
function getURLParams() {
	var match,
		pl     = /\+/g,  // Regex for replacing addition symbol with a space
		search = /([^&=]+)=?([^&]*)/g,
		decode = function (s) { return decodeURIComponent(s.replace(pl, " ")); },
		query  = window.location.search.substring(1);

	var urlParams = {};
	while (match = search.exec(query))
		urlParams[decode(match[1])] = decode(match[2]);

	return urlParams;
}

/**
 * Replaces a GET value in a URL
 * 	Source: http://stackoverflow.com/questions/7171099/how-to-replace-url-parameter-with-javascript-jquery
 */
function replaceUrlParam(url, paramName, paramValue){
	var pattern = new RegExp('\\b('+paramName+'=).*?(&|$)');

	if (url.search(pattern) >= 0)
		return url.replace(pattern,'$1' + paramValue + '$2');

	return url + (url.indexOf('?')>0 ? '&' : '?') + paramName + '=' + paramValue
}

/**
 * Creates a cookie
 * Source: http://www.w3schools.com/js/js_cookies.asp
 */
function setCookie(cname, cvalue, exdays) {
	if (exdays === undefined)
		exdays = 365;

	var d = new Date();
	d.setTime(d.getTime() + (exdays*24*60*60*1000));
	var expires = "expires="+d.toUTCString();
	document.cookie = cname + "=" + cvalue + "; " + expires + "; path=/";
}

/**
 * Get a cookie
 * Source: http://www.w3schools.com/js/js_cookies.asp
 */
function getCookie(cname, defaultValue) {
	var name = cname + "=";
	var ca = document.cookie.split(';');
	for(var i=0; i<ca.length; i++) {
		var c = ca[i];
		while (c.charAt(0)==' ') c = c.substring(1);
		if (c.indexOf(name) == 0) return c.substring(name.length,c.length);
	}

	return defaultValue;
}
