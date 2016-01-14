/**
 * Nodeview - Time range switch
 * Quickly change time range for every graph in the column
 */

$(document).ready(function() {
	var timeRangeSwitch = $('.timeRangeSwitch');

	timeRangeSwitch.find('ul > li').click(function() {
		if ($(this).hasClass('selected'))
			return;

		// Remove "selected" attribute
		$(this).parent().find('li').removeClass('selected');

		// Add "selected" class to this
		$(this).addClass('selected');

		var thisRSIndex = $(this).parent().parent().index();

		// Refresh all graphs in current column
		var newRange = $(this).text();
		$("img[data-col='" + thisRSIndex + "']").each(function() {
			$(this).data('graph').setTimeRange(newRange);
		});

		updateURL();
	});

	// Keep it on top of window on scroll
	var timeRangeSwitchContainer = $('.timeRangeSwitchContainer');
	var header = $('#header');
	$(window).scroll(function() {
		if ($(this).scrollTop() > header.height())
			timeRangeSwitchContainer.addClass('timeRangeFixed');
		else
			timeRangeSwitchContainer.removeClass('timeRangeFixed');
	});

	// There's a problem with CSS where time range switches do not wrap
	// on special resolutions. Let's fix it here
	$(window).resize(function() {
		var availableWidth = $('#content').width();
		if (timeRangeSwitch.first().outerWidth(true)*2 > availableWidth)
			timeRangeSwitch.css('display', 'block');
		else
			timeRangeSwitch.css('display', 'inline-block');
	});

	// Check if URL contains stuff like ?1=day&2=month
	var urlParams = getURLParams();
	if ('1' in urlParams)
		setTimeRange(0, urlParams['1']);
	if ('2' in urlParams)
		setTimeRange(1, urlParams['2']);
});

/**
 * Update current time range
 * @param columnIndex 0/1
 * @param val hour/day/...
 */
function setTimeRange(columnIndex, val) {
	$($('.timeRangeSwitch').find('ul')[columnIndex]).children().each(function() {
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

	var uls = $('.timeRangeSwitch').find('ul');
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
