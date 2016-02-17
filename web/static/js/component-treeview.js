/**
 * Domainview treeview
 */
(function($) {
	var Treeview = function(elem, options) {
		this.elem = $(elem);
		this.options = options;
		this.metadata = this.elem.data('treeview-options');
	};

	Treeview.prototype = {
		defaults: { },

		init: function() {
			var that = this;
			this.settings = $.extend({}, this.defaults, this.options, this.metadata);

			$('.toggle')
				.attr('data-expanded', 'true') // All toggles are expanded
				.click(function() {
					that.toggle($(this));
				});

			return this;
		},

		toggle: function(toggleButton) {
			if (toggleButton.attr('data-expanded') == 'true') { // Reduce it
				toggleButton.parent().next().hide();

				toggleButton
					.attr('data-expanded', 'false')
					.removeClass('mdi-chevron-down')
					.addClass('mdi-chevron-right');
			} else { // Expand it
				toggleButton.parent().next().show();

				toggleButton
					.attr('data-expanded', 'true')
					.removeClass('mdi-chevron-right')
					.addClass('mdi-chevron-down');
			}
		},

		expandAll: function() {
			var that = this;

			// Expand each reduced toggles
			$('[data-expanded=false]').each(function() {
				that.toggle($(this));
			});
		},

		reduceAll: function() {
			var that = this;

			// Reduce each reduced toggles
			$('[data-expanded=true]').each(function() {
				that.toggle($(this));
			});
		}
	};

	Treeview.defaults = Treeview.prototype.defaults;

	$.fn.treeview = function(options) {
		return new Treeview(this, options).init();
	};

	window.Treeview = Treeview;
}(jQuery));
