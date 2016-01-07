/**
 * Nodeview/comparison - Event ruler
 * Draw a vertical line in page to easily compare graphs
 *  (from an event for example)
 */
var test=0;
(function($, window) {
	// DOM elements
	var body,
		content,
		navWidth,
		eventRuler,
		eventRulerMT;

	var EventRuler = function(elem, options) {
		this.elem = elem;
		this.$elem = $(elem);
		this.options = options;
		this.metadata = this.$elem.data('eventruler-options');
	};

	EventRuler.prototype = {
		defaults: {
			eventRulerMTPadding: 10
		},

		init: function() {
			var that = this;
			this.settings = $.extend({}, this.defaults, this.options, this.metadata);

			// Init component
			this.body = $('body');
			this.content = $('#content');
			var nav = $('#nav');
			this.navWidth = nav.length ? nav.width() : 0;

			if (this.body.width() < 768) // Not possible with too small devices
				return this;

			// Append ruler and mask to document
			this.eventRulerMT = $('<div />')
				.attr('id', 'eventRulerMouseTrigger')
				.css('display', 'none')
				.append(
					this.eventRuler = $('<div />').attr('id', 'eventRuler')
				)
				.appendTo(this.body);

			// Register for <- and -> keys events
			$(document).keyup(function(e) {
				if ((e.keyCode == 37 || e.keyCode == 39) && that.eventRulerMT.is(':visible') && !$('#filter').is(':focus')) {
					var left = parseInt(that.eventRulerMT.css('left').replace('px', ''));

					var absVal = e.shiftKey ? 15 : 1;

					if (e.keyCode == 37)
						left -= absVal;
					else if (e.keyCode == 39)
						left += absVal;

					if (left+10 < that.navWidth)
						left = that.navWidth-10;

					that.eventRulerMT.css('left', left + 'px');
				}
			});

			// Add toggle in header
			var eventRulerToggle = $('<div />')
				.addClass('action-icon')
				.addClass('eventRulerToggle')
				.data('shown', false)
				.append(
					$('<i>').addClass('mdi').addClass('mdi-drag-vertical')
				)
				.appendTo($('header').find('.actions'));

			// Add listener
			eventRulerToggle.click(function(e) {
				e.stopPropagation();

				var shown = $(this).data('shown');

				$(this).data('shown', !shown);
				if (shown)
					$(this).removeClass('pressed');
				else
					$(this).addClass('pressed');

				that.toggleRuler();
			});

			// Tooltip
			eventRulerToggle.after('<div class="tooltip" style="right: 10px; left: auto;" data-dontsetleft="true">' +
				'<b>Toggle event ruler</b><br />Tip: use <b>&#8592;, &#8594;</b> or drag-n-drop to move once set,<br /><b>Shift</b> to move quicker</div>');
			prepareTooltips(eventRulerToggle, function(e) {
				return e.next();
			});

			return this;
		},

		toggleRuler: function() {
			var that = this;

			// Listen for mouse move, display ruler and ruler mask
			if (this.eventRulerMT.is(':visible')) {
				this.eventRulerMT.fadeOut();

				this.body.off('mousemove');
				this.body.off('click');
			} else {
				this.eventRulerMT.fadeIn();

				this.body.on('mousemove', function (e) {
					var left = e.pageX-that.settings.eventRulerMTPadding;

					if (left+10 < that.navWidth)
						left = that.navWidth-10;

					that.eventRulerMT.css('left', left);
				});

				this.body.on('click', function (e) {
					e.preventDefault();

					// Remove body events
					that.body.off('mousemove');
					that.body.off('click');

					var dragging = false;
					that.eventRulerMT.on('mousedown', function() {
						dragging = true;
					});
					that.body.on('mousemove', function(e) {
						if (dragging) {
							e.preventDefault(); // Prevent selection
							// Update ruler position
							var left = e.pageX-that.settings.eventRulerMTPadding;

							if (left+10 < that.navWidth)
								left = that.navWidth-10;

							that.eventRulerMT.css('left', left);
						}
					});
					that.eventRulerMT.on('mouseup', function() {
						dragging = false;
					});
				});
			}
		}
	};

	EventRuler.defaults = EventRuler.prototype.defaults;

	$.fn.eventRuler = function(options) {
		return this.each(function() {
			new EventRuler(this, options).init();
		});
	};

	window.EventRuler = EventRuler;
}(jQuery, window));
