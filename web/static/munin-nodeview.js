/**
 * Javascript executed on munin-nodeview page
 * Please note that there is also nodeview-timerangeswitch.js
 */

$(document).ready(function() {
	// Append a loading <img> on each graph img
	$('.graph').after('<img src="/static/loading.gif" class="graph_loading" style="display:none" />');

	// Auto-refresh
	startAutoRefresh();

	// Prepare filter
	prepareFilter('Filter graphs', function(val) {
		$('.graph').each(function() {
			var pluginName = $(this).attr('alt');
			var src = $(this).attr('src');
			var pluginId = src.substr(src.lastIndexOf('/')+1, src.lastIndexOf('-')-src.lastIndexOf('/')-1);

			if (filterMatches(val, pluginName) || filterMatches(val, pluginId)) {
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
