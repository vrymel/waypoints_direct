defmodule WaypointsDirect.Graph do

    alias WaypointsDirect.RouteEdge

    def new() do
        %{:vertices_count => 0, :edges_count => 0, :bags => %{}}
    end

    def add_edge(%{:bags => bags, :edges_count => edges_count} = graph, %RouteEdge{from_intersection_id: from_id, to_intersection_id: to_id}) do
        result = Map.get(bags, from_id)
        source_bag = unless result, do: [], else: result

        proceed_add = Enum.member?(source_bag, to_id)
        source_bag = unless proceed_add, do: [to_id | source_bag], else: source_bag

        unless proceed_add do
            new_bags = Map.put(bags, from_id, source_bag)

            %{graph | :bags => new_bags, :edges_count => edges_count + 1}
        else
            graph
        end
    end

    def adjacent(%{:bags => bags}, vertex) do
        bags[vertex]
    end

end