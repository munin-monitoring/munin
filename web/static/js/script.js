/**
 * Main UI script
 *  This file is included in every page
 */

$(document).ready(function() {
	// Navigation toggle on tablets
	$('#navToggle').click(function() {
		var nav = $('#nav');

		if ($(this).hasClass('expanded')) {
			$(this).removeClass('expanded');
			nav.hide();
		} else {
			$(this).addClass('expanded');
			nav.show();
		}
	});

	// Init toolbar component
	window.toolbar = $('header').toolbar();
});

/**
 * Binds click listener on one switchable (with the data-switch="id" attribute)
 * @param switchId Switch name
 */
function prepareSwitchable(switchId) {
	var switchable = $('.switchable[data-switch=' + switchId + ']');

	switchable.click(function() {
		var switchableContent = $('.switchable_content[data-switch=' + switchId + ']');

		if (switchableContent.is(':visible')) {
			switchableContent.hide();
			return;
		}

		switchableContent.css('left', $(this).position().left);
		switchableContent.css('top', $(this).position().top + $(this).height() + 10);
		switchableContent.show();

		// When clicking outside, hide the div
		$(document).bind('mouseup.switchable', function(e) {
			if (!switchableContent.is(e.target) // If we're neither clicking on switchableContent
				&& switchableContent.has(e.target).length === 0
				&& !switchable.is(e.target) // Same for switchable
				&& switchableContent.has(e.target).length === 0) { // nor on a descendent
				switchableContent.hide();

				// Unbind this event
				$(document).unbind('click.switchable');
			}
		});
	});

	// Gray out current element in switchable_content
	$('.switchable_content[data-switch=' + switchId + ']').children().filter(function() {
		return $.trim(switchable.text()) == $.trim($(this).text());
	}).addClass('current');
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
