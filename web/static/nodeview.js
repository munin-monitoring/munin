/**
 * Javascript executed on munin-nodeview page
 * Please note that there is also nodeview-timerangeswitch.js
 */

$(document).ready(function() {
	// Append a loading <img> on each graph img
	var images = $('.graph');
	var r_path = $('#r_path').val();
	images.after('<img src="' + r_path + '/static/loading.gif" class="graph_loading" style="display:none" />');

	// Register on image load event to hide loading styles
	images.on('load', function() {
		setImageLoading($(this), false);
	});

	// Auto-refresh
	setInterval(refreshGraphs, 5*60*1000);

	// Prepare filter
	prepareFilter('Filter graphs', function(val) {
		$('.graph').each(function() {
			var pluginName = $(this).attr('alt');
			var src = $(this).attr('src');
			var pluginId = src.substr(src.lastIndexOf('/')+1, src.lastIndexOf('-')-src.lastIndexOf('/')-1);

			if (pluginName.indexOf(val) != -1 || pluginId.indexOf(val) != -1) {
				$(this).parent().show();
				// Show plugin name
				$('h4').filter(function() {
					return $(this).text() == pluginName;
				}).show();

				// Show next <br>
				if ($(this).parent().next()[0].tagName.toLowerCase() == 'br')
					$(this).parent().next().show();
			}
			else {
				$(this).parent().hide();
				// Hidde plugin name
				$('h4').filter(function() {
					return $(this).text() == pluginName;
				}).hide();

				// Hide next <br>
				if ($(this).parent().next()[0].tagName.toLowerCase() == 'br')
					$(this).parent().next().hide();
			}
		});

		// Hide unneccary categories names
		$('div[data-category]').each(function() {
			if ($(this).children(':visible').length == 0)
				$(this).prev().hide();
			else
				$(this).prev().show();
		});
	});
});

/**
 * Tells UI that this specific image is loading (or not)
 *  (lowers opacity and shows loading spinner)
 */
function setImageLoading(imgDomElement, isLoading) {
	if (isLoading) {
		imgDomElement.css('opacity', '0.7');
		imgDomElement.next().show();
	} else {
		imgDomElement.css('opacity', '1');
		imgDomElement.next().hide();
	}
}

/**
 * Refresh every graph in this page
 */
function refreshGraphs() {
	$('.graph').each(function() {
		var src = $(this).attr('src');

		// Remove current timestamp if there is one
		if (src.indexOf('?') != -1)
			src = src.substring(0, src.indexOf('?'));

		// Add new timestamp
		src += '?' + new Date().getTime();

		setImageLoading($(this), true);

		$(this).attr('src', src);
	});
}
