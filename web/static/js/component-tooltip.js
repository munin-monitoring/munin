/**
 * Really simple tooltip component
 */
(function($, window) {
	var Tooltip = function(elem, message, options) {
		this.trigger = elem;
		this.$trigger = $(elem);
		this.message = message;
		this.options = options;
		this.metadata = this.$trigger.data('tooltip-options');
	};

	Tooltip.prototype = {
		defaults: {
			/** If true, <sup>?</sup> will be added to trigger */
			appendQuestionMark: false
		},

		init: function() {
			var that = this;
			this.settings = $.extend({}, this.defaults, this.options, this.metadata);

			// Create tooltip & append it to body
			this.tooltip = $('<div />')
				.addClass('tooltip')
				.html(this.message)
				.appendTo($('body'));

			// Append <sup>?</sup> to trigger
			if (this.settings.appendQuestionMark)
				this.$trigger.html(this.$trigger.text() + '<sup>?</sup>');

			// Register mouseenter event
			this.$trigger.mouseenter(function() {
				// Generate left & top tooltip position
				var triggerBottom = $(this).position().top + $(this).outerHeight(true);
				that.tooltip.css('top', triggerBottom);

				var left = $(this).position().left + $(this).outerHeight() / 2;
				that.tooltip.css('left', left);

				// TODO check if tooltip is out of view

				that.tooltip.fadeIn(100);
			});

			// Register mouseleave event
			this.$trigger.mouseleave(function() {
				that.tooltip.fadeOut(100);
			});
		}
	};

	Tooltip.defaults = Tooltip.prototype.defaults;

	$.fn.tooltip = function(message, options) {
		return this.each(function() {
			new Tooltip(this, message, options).init();
		});
	};

	window.Tooltip = Tooltip;
}(jQuery, window));
