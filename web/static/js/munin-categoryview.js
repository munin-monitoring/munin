/**
 * Javascript executed on munin-categoryview page
 */

var graphs,
	services;

$(document).ready(function() {
	graphs = $('.graph');
	services = $('.service');

	// Append a loading <img> on each graph img
	graphs.after('<img src="/static/img/loading.gif" class="graph_loading" style="display:none" />');

	// Auto-refresh
	startAutoRefresh();

	// Prepare filter
	prepareFilter('Filter graphs', function(val) {
		graphs.each(function() {
			var pluginName = $(this).attr('alt');
			var src = $(this).attr('src');
			var pluginId = src.substr(src.lastIndexOf('/')+1, src.lastIndexOf('-')-src.lastIndexOf('/')-1);

			if (filterMatches(val, pluginName) || filterMatches(val, pluginId)) {
				$(this).parent().parent().show();
			}
			else {
				$(this).parent().parent().hide();
			}
		});

		// Hide/show categories names
		// TODO not working when service is already hidden
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
