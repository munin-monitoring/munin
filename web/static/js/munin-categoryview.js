/**
 * Javascript executed on munin-categoryview page
 */

$(document).ready(function() {
	var graphs = window.graphs = $('.graph');
	var services = $('.service');

	// Instantiate auto-refresh & dynazoom modal links components
	var autoRefresh = graphs.autoRefresh();
	graphs.dynazoomModal();
	graphs.graph();

	addRefreshActionIcon(autoRefresh);

	// Prepare filter
	window.toolbar.prepareFilter('Filter graphs', function(val) {
		graphs.each(function() {
			var pluginName = $(this).attr('alt');
			var src = $(this).attr('src');
			var pluginId = src.substr(src.lastIndexOf('/')+1, src.lastIndexOf('-')-src.lastIndexOf('/')-1);

			if (window.toolbar.filterMatches(val, pluginName) || window.toolbar.filterMatches(val, pluginId)) {
				$(this).parent().parent().show();
			}
			else {
				$(this).parent().parent().hide();
			}
		});

		// Hide/show categories names
		// We can't just use the ':visible' selector since parent
		//	may be hidden
		services.each(function() {
			//if ($(this).children('.node:visible').length == 0)

			services.each(function() {
				if ($(this).children().filter(function() {
						return $(this).css('display') == 'none';
					}).length > 0)
					$(this).hide();
				else
					$(this).show();
			});
		});
	});
});
