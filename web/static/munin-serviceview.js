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
	var typeTds = $('td.type');
	typeTds.each(function() {
		var typeName = $(this).text();
		if (typeName in DEFINITIONS) {
			$(this).html(typeName + '<sup>?</sup>');
			$(this).append('<div class="typeTooltip">' + DEFINITIONS[typeName] + '</div>');
		}
	});
	typeTds.mouseenter(function() {
		var tooltip = $(this).find('.typeTooltip');
		tooltip.css('top', $(this).position().bottom);
		tooltip.css('left', $(this).position().left);
		tooltip.fadeIn(100);
	});
	typeTds.mouseleave(function() {
		$(this).find('.typeTooltip').fadeOut(100);
	});
});
