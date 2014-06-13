module.exports = ( grunt )->
	
	grunt.initConfig
		watch: 
			coffee: 
				files: ['_src/**/*.coffee', '_src_static/**/*.coffee']
				tasks: ['coffee']
		coffee: 
			server:
				expand: true
				cwd: '_src'
				src: ['*.coffee']
				dest: ''
				ext: '.js'
			modules:
			 	expand: true
			 	cwd: '_src/modules/'
			 	src: ['**/*.coffee']
			 	dest: 'modules'
			 	ext: '.js'
			static:
			 	expand: true
			 	cwd: '_src_static/'
			 	src: ['**/*.coffee']
			 	dest: 'static'
			 	ext: '.js'

	grunt.loadNpmTasks('grunt-contrib-coffee')
	grunt.loadNpmTasks('grunt-contrib-watch')

	grunt.registerTask('build', ['coffee'])
	grunt.registerTask('buildonsave', ['watch'])

	grunt.registerTask('default', ['build'])

	return