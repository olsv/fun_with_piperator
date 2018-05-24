require 'minitest/autorun'
require 'ostruct'
require 'piperator'
require 'pry'

class Payload < OpenStruct
  module IteratorWithNext
    def self.call(enumerable)
      prev = nil
      have_prev = false

      Enumerator.new do |yielder|
        enumerable.each do |item|
          have_prev ? yielder << [prev, item]  : have_prev = true
          prev = item
        end

        yielder << [prev, nil]
      end.lazy
    end
  end

  def put(path, value)
    Piperator::Pipeline
      .pipe(-> (path) { path.split('.').lazy })
      .pipe(IteratorWithNext)
      .pipe(-> (enum) { enum.reduce(self) { |acc, (this, that)| set(acc, this, that ? Hash.new : value) }})
      .call(path)
  end

  def retrieve(path)
    Piperator::Pipeline
      .pipe(-> (path) { path.split('.').lazy })
      .pipe(-> (enum) { enum.reduce(self) { |acc, chunk| get(acc, chunk) }})
      .call(path)
  end

  private

  def set(obj, key, value)
    case key
      when /(.+)\[(\d+)\]/
        obj[$1.to_sym] ||= Array.new
        obj[$1.to_sym][$2.to_i] ||= value
      else
        obj[key.to_sym] ||= value
    end
  end

  def get(obj, key)
    if obj.is_a?(Array)
      case key
        when /(.+)\[(\d+)\]/
          obj[$1][$2.to_i]
        when /(\d+)/
          obj[$1.to_i]
        else
          obj.select { |entry| entry && entry.has_key?(key.to_sym) }.map { |e| e[key.to_sym] }
      end
    else
      obj[key.to_sym]
    end
  end
end

class TestPayload < Minitest::Test
  def setup
    @payload = Payload.new
  end

  def test_simple_put
    @payload.put('some', 'value')
    assert_equal @payload.to_h, { some: 'value' }
  end

  def test_simple_nested_put
    @payload.put('some.path', 'value')
    assert_equal @payload.to_h, { some: { path: 'value' }}
  end

  def test_more_complex_nested_put
    @payload.put('some.complex.nested.path', 'value')
    assert_equal @payload.to_h, { some: { complex: { nested: { path: 'value' }}}}
  end

    def test_more_complex_consecutive_nested_put
    @payload.put('some.complex.nested.path', 'value1')
    @payload.put('some.complex.path', 'value2')
    @payload.put('some.complex.nested.other_path', 'value3')
    assert_equal @payload.to_h, { some: { complex: { path: 'value2', nested: { path: 'value1', other_path: 'value3' }}}}
  end

  def test_simple_array_put
    @payload.put( 'some[1]', 'value' )
    assert_equal @payload.to_h, { some: [nil, 'value'] }
  end

  def test_consecutive_simple_put
    @payload.put( 'some[1]', 'value1' )
    @payload.put( 'some[2]', 'value2' )
    assert_equal @payload.to_h, { some: [nil, 'value1', 'value2'] }
  end

  def test_nested_array_put
    @payload.put('some.nested[1]', 'value1')
    @payload.put('some.nested[2]', 'value2')
    assert_equal @payload.to_h, { some: { nested: [nil, 'value1', 'value2'] }}
  end

  def test_nested_array_with_hash_put
    @payload.put('some.nested[1].object', 'value1')
    @payload.put('some.nested[2]', 'value2')
    assert_equal @payload.to_h, { some: { nested: [nil, { object: 'value1' }, 'value2'] }}
  end

  def test_complex_nested_array_starting_with_array_put
    @payload.put('some[1].object.nested[1]', 'value')
    assert_equal @payload.to_h, { some: [nil,  object: { nested: [nil, 'value'] }] }
  end

  def test_real_example_put
    @payload.put('Events[0].Object.ObjectID', 33)
    @payload.put('Events[0].Object.ObjectType', 'Plate')
    @payload.put('Events[0].Object.OriginalBoundingBox[0]', 1578)
    @payload.put('Events[0].Object.OriginalBoundingBox[1]', 625)
    @payload.put('Events[0].Object.OriginalBoundingBox[2]', 1702)
    @payload.put('Events[0].Object.OriginalBoundingBox[3]', 665)
    @payload.put('Events[0].Object.RelativeID', 0)
    @payload.put('Events[0].Object.ShotFrame', true)
    @payload.put('Events[0].Object.Speed', 0)
    @payload.put('Events[0].Object.Text', 'EO2RW')

    expected = {
      Events: [
        Object: {
          ObjectID: 33,
          ObjectType: 'Plate',
          OriginalBoundingBox: [1578, 625, 1702, 665],
          RelativeID: 0,
          ShotFrame: true,
          Speed: 0,
          Text: 'EO2RW'
        }
      ]
    }

    assert_equal @payload.to_h, expected
  end

  def test_key_retrieve
    @payload.put('some', 'value')
    assert_equal @payload.retrieve('some'), 'value'
  end

  def test_nested_key_retrieve
    @payload.put('some.nested', 'value')
    assert_equal @payload.retrieve('some.nested'), 'value'
  end

  def test_array_key_retrieve
    @payload.put('some[1]', 'value')
    assert_equal @payload.retrieve('some'), [nil, 'value']
  end

  def test_array_nested_object_retrieve
    @payload.put('some[1].Object', 'value1')
    @payload.put('some[2].Object', 'value2')
    assert_equal @payload.retrieve('some.Object'), ['value1', 'value2']
  end

  def test_array_nested_complex_retrieve
    @payload.put('some[1].Object.Nested', 'value1')
    @payload.put('some[2].Object.Nested', 'value2')
    @payload.put('some[3].Object.Other', 'value3')
    assert_equal @payload.retrieve('some.Object.Nested'), ['value1', 'value2']
  end
end
