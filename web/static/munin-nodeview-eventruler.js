/**
 * Nodeview - Event ruler
 * Draw a vertical line in page to easily compare graphs
 *  (from an event for example)
 */

$(document).ready(function() {
    var body = $('body');
    // Append ruler and mask to document
    body.append('<div id="eventRulerMouseTrigger" style="display:none;"><div id="eventRuler"></div></div>');
    body.append('<div id="eventRulerMask" style="display:none;"></div>');

    // Register for <- and -> keys events
    var eventRulerMT = $('#eventRulerMouseTrigger');
    $(document).keyup(function(e) {
        if ((e.keyCode == 37 || e.keyCode == 39) && eventRulerMT.is(':visible') && !$('#filter').is(':focus')) {
            var left = parseInt(eventRulerMT.css('left').replace('px', ''));

            if (e.keyCode == 37)
                left--;
            else if (e.keyCode == 39)
                left++;

            eventRulerMT.css('left', left + 'px');
        }
    });
});

function toggleRuler() {
    // Listen for mouse move, display ruler and ruler mask
    var eventRulerMT = $('#eventRulerMouseTrigger');
    var eventRulerMTPadding = 10;
    var eventRulerMask = $('#eventRulerMask');
    var body = $('body');
    var content = $('#content');

    if (eventRulerMT.is(':visible')) {
        eventRulerMT.fadeOut();
        eventRulerMask.fadeOut();

        body.off('mousemove');
        body.off('click');
    } else {
        eventRulerMT.fadeIn();
        eventRulerMask.fadeIn();

        body.on('mousemove', function (e) {
            eventRulerMT.css('left', (e.pageX-eventRulerMTPadding)+'px');
        });

        body.on('click', function (e) {
            e.preventDefault();

            // Remove body events
            body.off('mousemove');
            body.off('click');

            eventRulerMask.fadeOut();

            var dragging = false;
            eventRulerMT.on('mousedown', function() {
                dragging = true;
            });
            body.on('mousemove', function(e) {
                if (dragging) {
                    e.preventDefault(); // Prevent selection
                    // Update ruler and handle positions
                    eventRulerMT.css('left', e.pageX+'px');
                    eventRulerMT.css('left', e.pageX-eventRulerMTPadding);
                }
            });
            eventRulerMT.on('mouseup', function() {
                dragging = false;
            });
        });
    }
}
