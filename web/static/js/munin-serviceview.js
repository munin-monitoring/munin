/**
 * Serviceview specific code
 */

var DEFINITIONS = {
	'gauge': 'A data source of type gauge shows the state of the data source at the '
			+ 'exact moment that Munin is run (every 5 minutes). Any peaks in-between data gatherings, will not be in '
			+ 'the graph.',
	'counter': 'A data source of type counter shows the state of the data source as an '
			+ 'average between two plots (i.e. 5 minutes). Short peaks will therefore be hard to spot, but long peaks '
			+ 'will be spottable, even though it occurs between plots.',
	'derive': 'For the purposes of viewing data, the derive type works the same way as a counter',
	'absolute': 'Absolute works much as a counter, with the exception that it is assumed '
			+ 'that the counter value is set to 0 upon each read of it. It\'s not a good idea to run these plugins by '
			+ 'hand in-between Munin runs, since Munin won\'t receive all the data it expects.'
};

$(document).ready(function() {
	// Legend type definitions tooltips
	var typeTds = $('td.type');
	typeTds.each(function() {
		var typeName = $(this).text();
		if (typeName in DEFINITIONS) {
			$(this).tooltip('<b>' + typeName + '</b>: ' + DEFINITIONS[typeName], {
				appendQuestionMark: true
			});
		}
	});

	var graphs = window.graphs = $('.graph');
	// Graphs auto-refresh
	var autoRefresh = graphs.autoRefresh();
	graphs.graph();

	addRefreshActionIcon(autoRefresh);

	// Switch to another graph in the same node
	$('.switchable[data-switch="header"]').list('header', {
		list: $('.switchable_content[data-switch="header"]')
	});
});
