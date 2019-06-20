#!/usr/bin/ruby

require 'json'
require 'open-uri'

@test = false
if ARGV[0] == '-t' then
	@test = true
	ARGV.shift
end

@languages = Hash[JSON.parse(File.open('language-codes.json').read).map { |l| [ l['alpha2'], l['English'].split(/;/).first ] }]

# Number of time to retry on failure
TRIES = 4

def pick_word
	`shuf -n1 words`.chomp
end

def article(word)
	if not word.match(/^(a |an |the )/i) then
		if word.match(/^[aeiou]/i) then
			word = "an #{word}"
		else
			word = "a #{word}"
		end
	end
	return word
end

def clean(word)
	word.gsub(/[- ]/, '_')
end

def get_cn_edges(word)
	cn = JSON.parse(open("http://api.conceptnet.io/c/en/#{clean(word)}").read)
	#puts JSON.pretty_generate(cn)
	return cn['edges']
end

def parse_edges(edges, thing)
	yourman = []

	edges.each do |edge|

		puts "#{edge['rel']['@id']} #{edge['start']['@id']} #{edge['end']['@id']} - #{edge['start']['label']} #{edge['rel']['label']} #{edge['end']['label']}" if @test

		edgeout = nil

		if edge['start']['@id'].match(/\/c\/en\/#{clean(thing)}(\/n)?/) then
			# relationship of our thing to something else
			case edge['rel']['@id']
			when '/r/IsA'
				edgeout = "is #{article(edge['end']['label'])}"
			when '/r/AtLocation'
				edgeout = "can be found in #{edge['end']['label']}"
			when '/r/RelatedTo'
				edgeout = "is related to #{edge['end']['label']}"
			when '/r/UsedFor'
				edgeout = "can be used for #{edge['end']['label']}"
			when '/r/CapableOf'
				edgeout = "can #{edge['end']['label']}"
			when '/r/HasContext'
				edgeout = "is related to #{edge['end']['label']}"
			when '/r/Causes'
				edgeout = "causes #{edge['end']['label']}"
			when '/r/DistinctFrom'
				edgeout = "is not #{edge['end']['label']}"
			when '/r/HasProperty'
				edgeout = "is #{edge['end']['label']}"
			when '/r/PartOf'
				edgeout = "is part of #{edge['end']['label']}"
			when '/r/HasA'
				edgeout = "has #{edge['end']['label']}"
			when '/r/ReceivesAction'
				edgeout = "can be #{edge['end']['label']}"
			when '/r/Synonym'
				edgeout = "can be called #{edge['end']['label']}"
			end

			# ConceptNet is inconsistently capitalised
			edgeout.downcase! if edgeout

			if edgeout and not edge['end']['language'] == 'en' then
				if @languages.has_key?(edge['end']['language']) then
					edgeout += " in #{@languages[edge['end']['language']]}"
				end
			end
		elsif edge['end']['@id'].match(/\/c\/en\/#{clean(thing)}(\/n)?/) then
			# relationship of something else to our thing
			case edge['rel']['@id']
			when '/r/IsA'
				edgeout = "is #{article(edge['start']['label'])}"
			when '/r/AtLocation'
				edgeout = "can contain #{edge['start']['label']}"
			when '/r/RelatedTo'
				edgeout = "is related to #{edge['start']['label']}"
			when '/r/UsedFor'
				edgeout = "can be used for #{edge['start']['label']}"
			when '/r/PartOf'
				edgeout = "has #{article(edge['start']['label'])}"
			when '/r/HasPrerequisite'
				edgeout = "is required for #{edge['start']['label']}"
			when '/r/Synonym'
				edgeout = "can be called #{edge['start']['label']}"
			end

			edgeout.downcase! if edgeout

			if edgeout and not edge['start']['language'] == 'en' then
				if @languages.has_key?(edge['start']['language']) then
					edgeout += " in #{@languages[edge['start']['language']]}"
				end
			end
		end

		yourman << edgeout if edgeout

	end
	return yourman
end

lines = []
try = 0
while try < TRIES
	begin
		if ARGV.empty? then
			thing = pick_word
		else
			thing = ARGV[0]
		end
		edges = get_cn_edges(thing)
		lines = parse_edges(edges, thing)
	rescue => e
		# probably ConceptNet lookup failed
		STDERR.puts "#{e.inspect} try=#{try} thing=#{thing.inspect}"
		try += 1
		# exponential backoff
		sleep (try * try) if try < TRIES
		next
	end
	if lines.empty? then
		# probably ConceptNet has nothing for us, try another word
		STDERR.puts "lines empty try=#{try} thing=#{thing.inspect}"
		try += 1
		sleep 1
		next
	else
		break
	end
end

if lines.empty? then
	STDERR.puts "lines empty tries exhausted"
	exit 1
end

if @test then
	out = lines.map{ |s| "- #{s}" }.join("\n")
else
	selected_lines = lines.select { |m| not m.match(/can be called/) }
	# select only one synonym line to avoid flooding with them
	selected_lines += lines.select { |m| m.match(/can be called/) }.sample(1)
	out  = "Ladies, if your man:\n\n"
	out += selected_lines.uniq.sample(5).map{ |s| "- #{s}" }.join("\n")
	out += "\n\nHe's not your man. He's #{article(thing)}."
end

puts out
