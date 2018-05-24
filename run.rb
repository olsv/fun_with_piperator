#!/usr/bin/env ruby
require 'pry'
require 'piperator'
require_relative 'payload'

CRLF = "\r\n"

module Reader
  def self.call(file)
    file = File.open(file, 'r')

    Enumerator.new do |yielder|
      file.each_line do |line|
        if line.match(/--myboundary/)
          text_body = file.readline.match(/Content-Type: text\/plain/)
          size = file.readline.match(/Content-Length: (\d+)/) && $1.to_i

          if text_body && size
            file.readline # one line after size
            yielder << file.read(size)
          end
        end
      end
    end.lazy
  end
end

module Parser
  def self.call(enumerable)
    Enumerator.new do |yielder|
      enumerable.each do |chunk|
        storage = Payload.new

        yielder << Piperator::Pipeline
          .pipe(-> (text) { text.split(CRLF) })
          .pipe(-> (enum) { enum.map { |r| r.split('=') }})
          .pipe(-> (enum) { enum.each_with_object(storage) { |(path, val), obj| obj.put(path, val) }})
          .call(chunk)
      end
    end.lazy
  end
end

module Fetcher
  def self.call(enumerable)
    Enumerator.new do |yielder|
      enumerable.each do |struct|
        yielder << struct.retrieve('Events.Object.Text')
      end
    end.lazy
  end
end

p Piperator::Pipeline
  .pipe(Reader)
  .pipe(Parser)
  .pipe(Fetcher)
  .call('test.cgi')
  .to_a
