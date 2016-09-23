/**
 * Component - Time range switch
 * Quickly change time range for every graph in the column
 */

$(document).ready(function() {
	var actionIcon = window.toolbar.addActionIcon('mdi-clock', 'Change time range', false, null);
	actionIcon.list('timeRangeSwitches', {
		list: $('#switchable_timeRange'),
		positionReference: $('header').find('.overflow'),
		width: '270px'
	});

	$('.timeRangeSwitch').find('li').click(function() {
		if ($(this).hasClass('selected'))
			return;

		// Update "selected" attribute
		$(this).parent().find('li').removeClass('selected');
		$(this).addClass('selected');

		var thisRSIndex = $(this).parent().attr('data-col');

		// Refresh all graphs in current column
		var newRange = $(this).text();
		$("img[data-col='" + thisRSIndex + "']").each(function() {
			$(this).data('graph').setLoading(true).setTimeRange(newRange);
		});

		updateURL();
	});

	// Check if URL contains stuff like ?1=day&2=month
	var urlParams = getURLParams();
	if (1 in urlParams)
		setTimeRange(0, urlParams['1']);
	if (2 in urlParams)
		setTimeRange(1, urlParams['2']);
});

/**
 * Update current time range
 * @param columnIndex 0/1
 * @param val hour/day/...
 */
function setTimeRange(columnIndex, val) {
	$($('.timeRangeSwitch')[columnIndex]).children().each(function() {
		if ($(this).text() == val)
			$(this).click();
	});
}

/**
 * Time ranges are added to URL whenever they change so they are kept when
 * 	refreshing the page / copy-pasting URL
 */
function updateURL() {
	// Check if history.pushState is supported by user's browser
	if (!history.pushState)
		return;

	var uls = $('.timeRangeSwitch');
	var firstTR = $(uls[0]).find('.selected').text();
	var secondTR = $(uls[1]).find('.selected').text();

	var qs = new Querystring();
	// Set 1 & 2 params
	qs.set('1', firstTR);
	qs.set('2', secondTR);

	// Get result as URL-ready string
	var url = $.param(qs.params);

	var pageName = $(document).find('title').text();
	window.history.replaceState('', pageName, '?' + url);
}
