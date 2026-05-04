class Point
  attr_accessor :x, :y
  def initialize(x, y); @x, @y = x, y; end
  def ==(other); @x == other.x && @y == other.y; end
  def to_s; "(#{@x}, #{@y})"; end
end

class Wire
  attr_accessor :p1, :p2
  def initialize(x1, y1, x2, y2)
    @p1 = Point.new(x1, y1)
    @p2 = Point.new(x2, y2)
  end

  # Checks if a point lies on the wire segment (supporting T-junctions)
  def contains?(point)
    # Check if point is within the bounding box of the wire
    return false unless point.x.between?([p1.x, p2.x].min, [p1.x, p2.x].max) &&
                        point.y.between?([p1.y, p2.y].min, [p1.y, p2.y].max)

    # Check for collinearity using cross product (handles vertical/horizontal/diagonal)
    (p2.y - p1.y) * (point.x - p1.x) == (point.y - p1.y) * (p2.x - p1.x)
  end
end

def find_auto_junctions(wires)
  junctions = []

  wires.each_with_index do |wire_a, i|
    wires.each_with_index do |wire_b, j|
      next if i == j # Skip comparing wire with itself

      # KiCad logic: A junction is created when a wire endpoint (p1 or p2) 
      # from wire_a lands exactly on wire_b.
      [wire_a.p1, wire_a.p2].each do |endpoint|
        if wire_b.contains?(endpoint)
          junctions << endpoint unless junctions.any? { |j_pt| j_pt == endpoint }
        end
      end
    end
  end
  junctions
end

# Example: A horizontal wire intersected by a vertical wire (T-junction)
wires = [
  Wire.new(0, 50, 100, 50), # Horizontal wire
  Wire.new(50, 0, 50, 50)   # Vertical wire ending AT the horizontal one
]

puts "Detected Junctions:"
find_auto_junctions(wires).each { |j| puts "Junction at: #{j}" }