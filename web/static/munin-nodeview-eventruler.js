/**
 * Nodeview - Event ruler
 * Draw a vertical line in page to easily compare graphs
 *  (from an event for example)
 */

$(document).ready(function() {
    var body = $('body');
    // Append ruler and mask to document
    body.append('<div id="eventRulerMouseTrigger" style="display:none;"><div id="eventRuler"></div></div>');

    // Register for <- and -> keys events
    var eventRulerMT = $('#eventRulerMouseTrigger');
    $(document).keyup(function(e) {
        if ((e.keyCode == 37 || e.keyCode == 39) && eventRulerMT.is(':visible') && !$('#filter').is(':focus')) {
            var left = parseInt(eventRulerMT.css('left').replace('px', ''));

            var absVal = e.shiftKey ? 15 : 1;

            if (e.keyCode == 37)
                left -= absVal;
            else if (e.keyCode == 39)
                left += absVal;

            eventRulerMT.css('left', left + 'px');
        }
    });

    // Add toggle in header (not on mobiles)
    if (body.width() > 768) {
        $('.header').find('.logo')
            .after('<div id="eventRulerToggle" class="eventRulerToggle" data-shown="false">' +
                        '<img src="/static/icons/eventrulerhandle.png" /></div>');
        var eventRulerToggle = $('#eventRulerToggle');
        eventRulerToggle.click(function(e) {
            e.stopPropagation();
            $(this).attr('data-shown', $(this).attr('data-shown') == 'false' ? 'true' : 'false');
            toggleRuler();
        });

        eventRulerToggle.after('<div class="tooltip" style="right: 10px; left: auto;" data-dontsetleft="true">' +
        '<b>Toggle event ruler</b><br />Tip: use <b>&#8592;, &#8594;</b> or drag-n-drop to move once set,<br /><b>Maj</b> to move quicker</div>');
        prepareTooltips(eventRulerToggle, function(e) { return e
            .next(); });
    }
});

function toggleRuler() {
    // Listen for mouse move, display ruler and ruler mask
    var eventRulerMT = $('#eventRulerMouseTrigger');
    var eventRulerMTPadding = 10;
    var body = $('body');
    var content = $('#content');

    if (eventRulerMT.is(':visible')) {
        eventRulerMT.fadeOut();

        body.off('mousemove');
        body.off('click');
    } else {
        eventRulerMT.fadeIn();

        body.on('mousemove', function (e) {
            eventRulerMT.css('left', (e.pageX-eventRulerMTPadding)+'px');
        });

        body.on('click', function (e) {
            e.preventDefault();

            // Remove body events
            body.off('mousemove');
            body.off('click');

            var dragging = false;
            eventRulerMT.on('mousedown', function() {
                dragging = true;
            });
            body.on('mousemove', function(e) {
                if (dragging) {
                    e.preventDefault(); // Prevent selection
                    // Update ruler position
                    eventRulerMT.css('left', e.pageX-eventRulerMTPadding);
                }
            });
            eventRulerMT.on('mouseup', function() {
                dragging = false;
            });
        });
    }
}
