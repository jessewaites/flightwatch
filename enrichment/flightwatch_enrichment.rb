# frozen_string_literal: true

require "csv"
require "json"
require "net/http"
require "uri"

module FlightWatch
  module Enrichment
    ROOT = File.expand_path(__dir__)
    FIXTURES = File.join(ROOT, "fixtures")
    AIRPORTS_URL = "https://davidmegginson.github.io/ourairports-data/airports.csv"
    METAR_URL = "https://aviationweather.gov/api/data/metar"

    module_function

    def for_flag(flag, offline: false)
      airport = safe_lookup { nearest_airport(flag["lat"], flag["lon"], offline: offline) } ||
                nearest_airport_from_fixture(flag["lat"], flag["lon"])
      station = airport.fetch("ident", "KBOS")
      metar = safe_lookup { fetch_metar(station, offline: offline) } ||
              fixture_metar(station) ||
              fixture_metar("KBOS")
      aircraft_type = safe_lookup { aircraft_type(flag["icao24"], flag.dig("evidence", "callsign")) } ||
                      "unknown"

      {
        "metar" => metar.to_s.strip,
        "nearest_airport" => station,
        "aircraft_type" => aircraft_type,
        "surface_context" => surface_context(flag, airport),
        "nearest_airport_nm" => airport["distance_nm"]
      }
    rescue StandardError
      {
        "metar" => fixture_metar("KBOS"),
        "nearest_airport" => "KBOS",
        "aircraft_type" => "unknown",
        "surface_context" => "KBOS terminal area",
        "nearest_airport_nm" => nil
      }
    end

    def fetch_metar(station, offline: false)
      raise "offline" if offline

      uri = URI(METAR_URL)
      uri.query = URI.encode_www_form("ids" => station, "format" => "raw")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 4, open_timeout: 3) do |http|
        http.get(uri.request_uri)
      end
      raise "metar http #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      body = response.body.to_s.strip.lines.first.to_s.strip
      raise "empty metar" if body.empty?

      body
    end

    def fixture_metar(station)
      path = File.join(FIXTURES, "metar", "#{station}.txt")
      path = File.join(FIXTURES, "metar", "KBOS.txt") unless File.exist?(path)
      File.read(path).strip
    rescue StandardError
      "KBOS 261854Z 21012KT 10SM FEW045 24/12 A3001"
    end

    def nearest_airport(lat, lon, offline: false)
      rows = airports_rows(offline: offline)
      nearest = nearest_airport_row(rows, lat.to_f, lon.to_f)
      raise "no airport rows" unless nearest

      nearest
    end

    def nearest_airport_from_fixture(lat, lon)
      nearest_airport_row(airports_rows(offline: true), lat.to_f, lon.to_f) ||
        { "ident" => "KBOS", "name" => "Boston Logan International Airport", "distance_nm" => nil }
    end

    def airports_rows(offline: false)
      csv = if offline
              File.read(File.join(FIXTURES, "airports.csv"))
            else
              fetch_airports_csv
            end
      CSV.parse(csv, headers: true).select do |row|
        ident = row["ident"].to_s
        country = row["iso_country"].to_s
        type = row["type"].to_s
        ident.start_with?("K") && country == "US" && type.end_with?("airport")
      end
    rescue StandardError
      CSV.parse(File.read(File.join(FIXTURES, "airports.csv")), headers: true)
    end

    def fetch_airports_csv
      uri = URI(AIRPORTS_URL)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 6, open_timeout: 3) do |http|
        http.get(uri.request_uri)
      end
      raise "airports http #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response.body
    end

    def nearest_airport_row(rows, lat, lon)
      row, distance = rows.map do |airport|
        alat = airport["latitude_deg"].to_f
        alon = airport["longitude_deg"].to_f
        [airport, distance_nm(lat, lon, alat, alon)]
      end.min_by { |_airport, nm| nm }
      return nil unless row

      row.to_h.merge("distance_nm" => distance.round(1))
    end

    def aircraft_type(icao24, callsign = nil)
      rows = CSV.read(File.join(FIXTURES, "aircraft_types.csv"), headers: true)
      row = rows.find { |r| r["icao24"].to_s.downcase == icao24.to_s.downcase }
      row ||= rows.find { |r| !callsign.to_s.empty? && r["callsign"].to_s.strip == callsign.to_s.strip }
      row && row["aircraft_type"].to_s
    end

    def surface_context(flag, airport)
      lat = flag["lat"].to_f
      lon = flag["lon"].to_f
      nearest = airport["ident"].to_s
      distance = airport["distance_nm"]

      if nearest == "KBOS" && distance && distance <= 8.0
        "KBOS terminal approach area"
      elsif lon > -70.98 && lat.between?(42.25, 42.48)
        "Massachusetts Bay / open water east of Boston"
      elsif nearest == "KBOS" && distance && distance <= 18.0
        "KBOS arrival corridor"
      else
        "Boston-area airspace"
      end
    end

    def safe_lookup
      yield
    rescue StandardError
      nil
    end

    def distance_nm(lat1, lon1, lat2, lon2)
      radius_nm = 3440.065
      dlat = radians(lat2 - lat1)
      dlon = radians(lon2 - lon1)
      a = Math.sin(dlat / 2)**2 +
          Math.cos(radians(lat1)) * Math.cos(radians(lat2)) * Math.sin(dlon / 2)**2
      2 * radius_nm * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    end

    def radians(degrees)
      degrees * Math::PI / 180.0
    end
  end
end
