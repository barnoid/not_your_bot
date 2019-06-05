#!/usr/bin/ruby

require 'json'
require 'open-uri'

@test = false
if ARGV[0] == '-t' then
	@test = true
	ARGV.shift
end

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

		if edge['start']['@id'].match(/\/c\/en\/#{clean(thing)}(\/n)?/) then
			# relationship of our thing to something else
			case edge['rel']['@id']
			when '/r/IsA'
				yourman << "is #{article(edge['end']['label'])}"
			when '/r/AtLocation'
				yourman << "can be found in #{edge['end']['label']}"
			when '/r/RelatedTo'
				yourman << "is related to #{edge['end']['label']}"
			when '/r/UsedFor'
				yourman << "can be used for #{edge['end']['label']}"
			when '/r/CapableOf'
				yourman << "can #{edge['end']['label']}"
			when '/r/HasContext'
				yourman << "is related to #{edge['end']['label']}"
			when '/r/Causes'
				yourman << "causes #{edge['end']['label']}"
			when '/r/DistinctFrom'
				yourman << "is not #{edge['end']['label']}"
			when '/r/HasProperty'
				yourman << "is #{edge['end']['label']}"
			when '/r/PartOf'
				yourman << "is part of #{edge['end']['label']}"
			when '/r/HasA'
				yourman << "has #{edge['end']['label']}"
			when '/r/ReceivesAction'
				yourman << "can be #{edge['end']['label']}"
			end
		elsif edge['end']['@id'].match(/\/c\/en\/#{clean(thing)}(\/n)?/) then
			# relationship of something else to our thing
			case edge['rel']['@id']
			when '/r/IsA'
				yourman << "is #{article(edge['start']['label'])}"
			when '/r/AtLocation'
				yourman << "can contain #{edge['start']['label']}"
			when '/r/RelatedTo'
				yourman << "is related to #{edge['start']['label']}"
			when '/r/UsedFor'
				yourman << "can be used for #{edge['start']['label']}"
			when '/r/PartOf'
				yourman << "has #{article(edge['start']['label'])}"
			when '/r/HasPrerequisite'
				yourman << "is required for #{edge['start']['label']}"
			end
		end

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
	out = lines.map{ |s| "- #{s.downcase}" }.join("\n")
else
	out  = "Ladies, if your man:\n\n"
	out += lines.uniq.sample(5).map{ |s| "- #{s.downcase}" }.join("\n")
	out += "\n\nHe's not your man. He's #{article(thing)}."
end

puts out
