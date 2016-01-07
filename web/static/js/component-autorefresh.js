/**
 * Graphs auto-refresh
 */
(function($, window) {
	var AutoRefresh = function(elems, options) {
		this.graphs = $(elems);
		this.options = options;
		this.metadata = this.graphs.data('autorefresh-options');
	};

	AutoRefresh.prototype = {
		defaults: { },

		init: function() {
			this.settings = $.extend({}, this.defaults, this.options, this.metadata);

			// Register on image load + error events to hide loading styles
			var that = this;
			this.graphs.on('load error', function() {
				that.setImageLoading($(this), false);
			});

			// Copy current src attribute as backup in an attribute
			this.graphs.each(function() {
				$(this).attr('data-autorefresh-src', $(this).attr('src'));
			});

			setInterval(function() {
				that.refreshGraphs.call(that);
			}, 5*60*1000);

			return this;
		},

		setImageLoading: function(imgDomElement, isLoading) {
			if (isLoading) {
				imgDomElement.parent().css('opacity', '0.7');
				imgDomElement.parent().find('.graph_loading').show();
			} else {
				imgDomElement.parent().css('opacity', '1');
				imgDomElement.parent().find('.graph_loading').hide();
			}
		},

		refreshGraphs: function() {
			var that = this;

			this.graphs.each(function() {
				var graph = $(this);
				var src = graph.attr('data-autorefresh-src');

				// Add new timestamp
				var prefix = src.indexOf('?') != -1 ? '&' : '?';
				src += prefix + new Date().getTime();

				that.setImageLoading(graph, true);

				// Since we change the src attr, we have to reattach
				// the error event
				graph.on('error', function() {
					that.setImageLoading(graph, false);
				});

				graph.attr('src', src);
			});
		}
	};

	AutoRefresh.defaults = AutoRefresh.prototype.defaults;

	$.fn.autoRefresh = function(options) {
		return new AutoRefresh(this, options).init();
	};

	// Make setImageLoading accessible without selector
	$.autoRefresh = {
		setImageLoading: AutoRefresh.prototype.setImageLoading
	};

	window.AutoRefresh = AutoRefresh;
}(jQuery, window));
