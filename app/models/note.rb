class Note < ActiveRecord::Base
  belongs_to :user
  has_many :collections, :dependent => :destroy
  has_many :albums, :through => :collections

  has_many :stars, :dependent => :destroy
  has_many :users, :through => :stars

  before_save :set_point
  before_update :set_point

  validates :title, :body, :user_id, presence: true
  validates :latitude, :longitude, :user_id, numericality: true

  # By default, use the GEOS implementation for spatial columns
  self.rgeo_factory_generator = RGeo::Geos.method(:factory)

  # But use a geographic implementation for the :latlon column.
  set_rgeo_factory_for_column(:latlon, RGeo::Geographic.spherical_factory)

  # Uses lat and lng to create and set point within note
  def set_point
    if self.latitude_was != self.latitude || self.longitude_was != self.longitude
      self[:latlon] = RGeo::Geographic.spherical_factory(:srid => 4326)
                          .point(self[:longitude], self[:latitude])
    end
  end

  # Finds all public and user's notes close to location to certain degree
  def Note.find_by_proximity(location, degree, current_user)
    linestring_text = get_linestring_text(location, degree)
    user_notes = Note.find_by_sql("
            SELECT id, latitude, longitude, user_id
            FROM notes
            FORCE INDEX (index_notes_on_latlon)
            WHERE
              user_id=#{current_user.id} AND
              MBRContains(GeomFromText( '#{linestring_text}' ), notes.latlon)")
    # order first by day (not time), then by star count
    pub_notes = Note.find_by_sql("
            SELECT id, latitude, longitude, user_id
            FROM notes
            FORCE INDEX (index_notes_on_latlon)
            WHERE
              private=false AND user_id!=#{current_user.id} AND
              MBRContains(GeomFromText( '#{linestring_text}' ), notes.latlon)
            ORDER BY LEFT(created_at, 10) DESC, star_count DESC LIMIT 30")
    user_notes + pub_notes
  end

  # Gets text representation of linestring centered around location
  def Note.get_linestring_text(location, degree)
    "LINESTRING(#{location.lng - degree} #{location.lat - degree},
                #{location.lng + degree} #{location.lat + degree})"
  end
end
