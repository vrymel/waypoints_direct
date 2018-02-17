defmodule WaypointsDirectWeb.GraphApiController do
    use WaypointsDirectWeb, :controller

    alias WaypointsDirect.Graph
    alias WaypointsDirect.GraphUtils
    alias WaypointsDirect.GeoPoint
    alias WaypointsDirect.DijkstraShortestPath
    alias WaypointsDirect.RouteEdge
    alias WaypointsDirect.Intersection

    @within_radius 0.200 # within 200 meters radius
    @earth_radius 6371 # approximate radius of the Earth in km

    def search_path(conn, %{"from" => from_coordinates, "to" => to_coordinates}) do
      %{"lat" => from_lat, "lng" => from_lng} = Poison.decode! from_coordinates
      %{"lat" => to_lat, "lng" => to_lng} = Poison.decode! to_coordinates

      within = @within_radius / @earth_radius
      from_geopoint = GeoPoint.from_degrees(%GeoPoint{lat: from_lat, lng: from_lng})
      to_geopoint = GeoPoint.from_degrees(%GeoPoint{lat: to_lat, lng: to_lng})

      %Intersection{:id => from_intersection_id} = get_nearest_intersection(from_geopoint, within)
      %Intersection{:id => to_intersection_id} = get_nearest_intersection(to_geopoint, within)

      %{:path_exist => path_exist, :path => path} = do_search_path(build_graph(), from_intersection_id, to_intersection_id)

      # path is a list of route_edges, we need to translate it to
      # an intersection list so we end up with a complete path from
      # source to destination
      intersection_list = GraphUtils.route_edges_to_intersection_list(path)
      route_sequence = sequence(path, build_route_edge_lookup_table())

      route_clean = Enum.map(
        route_sequence, 
        fn(from_intersection) -> 
          Map.drop(from_intersection, [:intersection_pair])
        end
      )

      json conn, %{exist: path_exist, path: route_clean}
    end

    defp get_nearest_intersection(%GeoPoint{:lat => lat, :lng => lng}, radius) do
      distance_formula = "acos(sin($1::float) * sin(lat_radian) + cos($1::float) * cos(lat_radian) * cos(lng_radian - ($2::float)))"
 
      query_result = Repo.query("
        SELECT 
        id, 
        #{distance_formula} AS relative_distance 
        FROM intersections 
        WHERE #{distance_formula} <= $3::float", [lat, lng, radius])

      case query_result do
        {:ok, result} ->
          %{:rows => rows } = Map.take(result, [:rows])

          unless rows == [] do
            [nearest_id, _] = Enum.reduce rows, fn([_r_id, r_distance] = row, [_acc_id, acc_distance] = acc) ->
              if r_distance < acc_distance, do: row, else: acc
            end

            Repo.get Intersection, nearest_id
          end
        _ -> 
          nil
      end
    end

    defp do_search_path(graph, source, destination) do
      tree = DijkstraShortestPath.init_tree source
      tree = DijkstraShortestPath.build_tree graph, tree

      path_exist = DijkstraShortestPath.path_exist? tree, destination
      path_to = DijkstraShortestPath.path_to tree, destination
      
      %{path_exist: path_exist, path: path_to}
    end

    defp get_route_edges do
      query = from re in RouteEdge, 
        join: fi in assoc(re, :from_intersection),
        join: ti in assoc(re, :to_intersection),
        preload: [from_intersection: fi, to_intersection: ti]

      Repo.all(query)
    end

    defp build_graph do
      get_route_edges() |> Enum.reduce(
          Graph.new(), 
          fn(re, graph) -> Graph.add_edge(graph, re) end
        )
    end

    defp build_route_edge_lookup_table do
      get_route_edges() |> Enum.reduce(%{}, fn(%RouteEdge{:from_intersection_id => fid, :to_intersection_id => tid, :route_id => route_id}, table) -> 
            intersection_pair = {fid, tid}
            bag = Map.get(table, intersection_pair)

            bag = if bag, do: MapSet.put(bag, route_id), else: MapSet.new() |> MapSet.put(route_id) 

            Map.put(table, intersection_pair, bag)
      end)
    end

    def intersection_pair(%RouteEdge{:from_intersection_id => fid, :to_intersection_id => tid}), do: {fid, tid}

    def sequence(route_edge_path, lookup) do
      %{intersections: intersections} = Enum.reduce(
        route_edge_path, 
        %{previous_intersect: MapSet.new(), intersections: [] }, 
        fn(re, %{:previous_intersect => previous_intersect, :intersections => intersections}) -> 
          intersection_map = to_intersection_map(re, :from_intersection)
          route_ids = Map.get(lookup, intersection_map.intersection_pair)

          intersecting_route_ids = MapSet.intersection(previous_intersect, route_ids)

          case MapSet.size(intersecting_route_ids) do
            0 -> 
              [first_route_id | _] = MapSet.to_list(route_ids)
              intersection_map = Map.put(intersection_map, :route_id, first_route_id)

              %{previous_intersect: route_ids, intersections: [intersection_map | intersections]}
            _ -> 
              [first_route_id | _] = MapSet.to_list(intersecting_route_ids)
              intersection_map = Map.put(intersection_map, :route_id, first_route_id)

              %{previous_intersect: intersecting_route_ids, intersections: [intersection_map | intersections]}
          end
        end
      )

      [ %{route_id: last_intersection_route_id} | _] = intersections
      [last_route_edge | _] = Enum.reverse(route_edge_path)
      last_intersection_map = to_intersection_map(last_route_edge, :to_intersection) |> Map.put(:route_id, last_intersection_route_id)

      Enum.reverse([last_intersection_map | intersections])
    end

    defp to_intersection_map(%RouteEdge{:from_intersection_id => fid, :to_intersection_id => tid} = route_edge, target_intersection_key) do
      %{:lat => lat, :lng => lng, :id => id} = Map.get(route_edge, target_intersection_key)
      intersection_pair = {fid, tid} 
    
      %{ intersection_id: id, lat: lat, lng: lng, intersection_pair: intersection_pair }
    end
end