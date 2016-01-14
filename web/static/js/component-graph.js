/**
 * Graph component
 */
(function($, window) {
	var TimeRanges = {
		Hour: 'hour',
		Day: 'day',
		Week: 'week',
		Month: 'month',
		Year: 'year'
	};

	var GraphFormats = {
		PNG: 'png',
		SVG: 'svg'
	};

	var Graph = function(elem, options) {
		this.elem = $(elem);
		this.options = options;
	};

	Graph.prototype = {
		defaults: {

		},

		init: function() {
			this.settings = $.extend({}, this.defaults, this.options);

			// Detect graph timerange & graph format
			var fileName = this.elem.attr('src');
			var matches = fileName.match(/-(hour|day|week|month|year)\.(png|svg)$/);

			this.timeRange = matches[1];
			this.fileFormat = matches[2];

			// For refresh method, copy current attribute as backup
			this.autorefreshSrc = this.elem.attr('src');

			// Register load & error event to hide loading styles
			this.registerLoadingEvents('load error');

			// Append spinner
			this.loadingSpinner = $('<img />')
				.attr('src', '/static/img/loading.gif')
				.addClass('graph_loading')
				.css('display', 'none')
				.insertBefore(this.elem);

			return this;
		},

		setTimeRange: function(timeRange) {
			this.timeRange = timeRange;

			// Replace src attribute
			var fileName = this.elem.attr('src');
			this.elem.attr('src', this.generateURLName(fileName, this.timeRange, this.fileFormat));
		},

		setFileFormat: function(fileFormat) {
			this.fileFormat = fileFormat;

			// Replace src attribute
			var fileName = this.elem.attr('src');
			this.elem.attr('src', this.generateURLName(fileName, this.timeRange, this.fileFormat));
		},

		refresh: function() {
			var src = this.autorefreshSrc;

			// Add new timestamp
			var prefix = src.indexOf('?') != -1 ? '&' : '?';
			src += prefix + new Date().getTime();

			// Since we change the src attr, we have to reattach the error event
			this.registerLoadingEvents('error');

			this.elem.attr('src', src);
			this.setLoading(true);
		},

		setLoading: function(isLoading) {
			if (isLoading) {
				this.elem.css('opacity', '0.7');
				this.loadingSpinner.show();
			} else {
				this.elem.css('opacity', '1');
				this.loadingSpinner.hide();
			}
		},

		registerLoadingEvents: function(events) {
			var that = this;
			this.elem.on(events, function() {
				that.setLoading(false);
			});
		},

		generateURLName: function(url, timeRange, fileFormat) {
			return url.replace(/-(hour|day|week|month|year)\.(png|svg)/, '-' + timeRange + '.' + fileFormat);
		}
	};

	Graph.defaults = Graph.prototype.defaults;
	Graph.TimeRanges = TimeRanges;
	Graph.GraphFormats = GraphFormats;

	$.fn.graph = function(options) {
		return this.each(function() {
			if (!$(this).data('graph'))
				$(this).data('graph', new Graph(this, options).init());
		});
	};

	window.Graph = Graph;
}(jQuery, window));
