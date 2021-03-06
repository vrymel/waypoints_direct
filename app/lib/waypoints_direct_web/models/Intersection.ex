defmodule WaypointsDirect.Intersection do
    use WaypointsDirectWeb, :model

    alias WaypointsDirect.RouteEdge

    schema "intersections" do
        field :description, :string
        field :lat, :float
        field :lng, :float
        field :lat_radian, :float
        field :lng_radian, :float

        # we need to define the column of a referencing model here
        # in this case, we define that the model `RouteEdge` has two columns
        # that references `Intersection`, :from_intersection_id and :to_intersection_id columns.
        # :from_route_edges and :to_route_edges are the association name
        has_many :from_route_edges, RouteEdge, foreign_key: :from_intersection_id
        has_many :to_route_edges, RouteEdge, foreign_key: :to_intersection_id

        timestamps()
    end

    def changeset(intersection, params \\ %{}) do
        intersection
        |> cast(params, [:description, :lat, :lng, :lat_radian, :lng_radian])
        # |> validate_required([:lat, :lng]) # temporarily disable validation for testing
    end
end