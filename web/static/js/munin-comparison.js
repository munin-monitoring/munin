/**
 * Comparison specific code
 */

var content,
	graphs,
	trs;

$(document).ready(function() {
	content = $('#content');
	graphs = $('.graph');
	trs = $('tr');

	// Append a loading <img> on each graph img
	graphs.after('<img src="/static/img/loading.gif" class="graph_loading" style="display:none" />');

	// Auto-refresh
	startAutoRefresh();

	// Prepare filter
	prepareFilter('Filter graphs', function(val) {
		trs.each(function() {
			var serviceName = $(this).data('servicename');
			var serviceTitle = $(this).data('servicetitle');

			if (filterMatches(val, serviceName) || filterMatches(val, serviceTitle)) {
				$(this).show();
			}
			else {
				$(this).hide();
			}
		});

		// Hide unnecessary categories names
		$('h3').each(function() {
			var table = $(this).next();
			if (table.find('tr:visible').length == 0)
				$(this).hide();
			else
				$(this).show();
		});
	});
});
