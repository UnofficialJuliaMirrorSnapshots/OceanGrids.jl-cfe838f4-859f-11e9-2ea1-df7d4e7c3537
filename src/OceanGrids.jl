module OceanGrids

using Unitful

abstract type OceanGrid end

"""
    OceanRectilinearGrid

Ocean rectilinear grid.
Here I use the slightly abuse the term rectilinear, 
because the grid supposedly represents layers around the (curved) globe.
Here "rectilinear" means that the grid is defined entirely by just its
`lat`, `lon`, `depth`, `δlat`, `δlon`, and `δdepth` vectors.
For example, the Ocean Circulation Inverse Model (OCIM) version 1 
grid is rectilinear in that sense.
"""
struct OceanRectilinearGrid <: OceanGrid
    lat          # °
    lon          # °
    depth        # m
    δlat         # °
    δlon         # °
    δdepth       # m
    lat_3D       # °
    lon_3D       # °
    depth_3D     # m
    δy           # m
    δx_3D        # m
    δy_3D        # m
    δz_3D        # m
    volume_3D    # m³
    depth_top    # m
    depth_top_3D # m
    A_2D         # m²
    nlon
    nlat
    ndepth
    nboxes
end

"""
    OceanCurvilinearGrid

Ocean curvilinear grid.
The grid is curvilinear if it can be accessed using Cartesian Indices.
I.e., it maps to a rectilinear grid.
This type of grid typically cannot be inferred from only
`lat`, `lon`, `depth`, `δlat`, `δlon`, and `δdepth` vectors.
Instead, the full 3-dimensional arrays
`lat_3D`, `lon_3D`, `D`epth_3D`, `δx_3D`, `δy_3D`, and `δz_3D`
are required.
For exaample, the displaced-pole grid of the POP model is curcvilinear.
"""
struct OceanCurvilinearGrid <: OceanGrid
    lat_3D       # °
    lon_3D       # °
    depth_3D     # m
    δx_3D        # m
    δy_3D        # m
    δz_3D        # m
    volume_3D    # m³
    depth_top    # m
    depth_top_3D # m
    A_2D         # m²
    nlon
    nlat
    ndepth
    nboxes
end

const TU = AbstractArray{<:Quantity}

"""
    OceanGrid(elon::T, elat::U, edepth::V; R=upreferred(6371.0u"km")) where {T<:TU, U<:TU, V<:TU}

Returns an `OceanRectilinearGrid` with boxes whose edges are defined by the
`elon`, `elat`, and `edepth` vectors.
The globe radius can be changed with the keyword `R` (default value 6371 km)
"""
function OceanGrid(elon::T, elat::U, edepth::V; R=upreferred(6371.0u"km")) where {T<:TU, U<:TU, V<:TU}
    nlon, nlat, ndepth = length(elon) - 1, length(elat) - 1, length(edepth) - 1
    nboxes = nlon * nlat * ndepth
    lon = edges_to_centers(elon)
    lat = edges_to_centers(elat)
    depth = edges_to_centers(edepth)
    δlon, δlat, δdepth = diff(elon), diff(elat), diff(edepth)
    # depth objects
    δz_3D = repeat(reshape(δdepth, (1,1,ndepth)), outer=(nlat,nlon,1))
    depth_3D = repeat(reshape(depth, (1,1,ndepth)), outer=(nlat,nlon,1))
    depth_top = cumsum(δdepth) - δdepth
    depth_top_3D = repeat(reshape(depth_top, (1,1,ndepth)), outer=(nlat,nlon,1))
    # lat objects
    R = R |> u"m" # convert to meters
    lat_3D = repeat(reshape(lat, (nlat,1,1)), outer=(1,nlon,ndepth))
    δy = R * δlat ./ 360u"°"
    δy_3D = repeat(reshape(δy, (nlat,1,1)), outer=(1,nlon,ndepth))
    # lon objects
    lon_3D = repeat(reshape(lon, (1,nlon,1)), outer=(nlat,1,ndepth))
    # For δx_3D, first calculate the area and then infer the equivalent distance in meters
    A_2D = R^2 * abs.(sin.(elat[1:end-1]) - sin.(elat[2:end])) * ustrip.(δlon .|> u"rad")'
    A_3D = repeat(A_2D, outer=(1, 1, ndepth))
    δx_3D = A_3D ./ δy_3D
    # volume
    volume_3D = δx_3D .* δy_3D .* δz_3D
    return OceanRectilinearGrid(
                     lat,          # °
                     lon,          # °
                     depth,        # m
                     δlat,         # °
                     δlon,         # °
                     δdepth,       # m
                     lat_3D,       # °
                     lon_3D,       # °
                     depth_3D,     # m
                     δy,           # m
                     δx_3D,        # m
                     δy_3D,        # m
                     δz_3D,        # m
                     volume_3D,    # m³
                     depth_top,    # m
                     depth_top_3D, # m
                     A_2D,         # m²
                     nlon,
                     nlat,
                     ndepth,
                     nboxes
                    )
end

edges_to_centers(x::Vector) = 0.5 * (x[1:end-1] + x[2:end])
edges_to_centers(x::AbstractRange) = x[1:end-1] .+ 0.5step(x)

"""
    OceanGrid(nlat::Int, nlon::Int, ndepth::Int)

Returns a regularly spaced `OceanRectilinearGrid` with size `nlat`, `nlon`, and `ndepth`.
"""
function OceanGrid(nlat::Int, nlon::Int, ndepth::Int)
    elat = range(-90,90,length=nlat+1) * u"°"
    elon = range(0,360,length=nlon+1) * u"°"
    edepth = range(0,3682,length=ndepth+1) * u"m"
    return OceanGrid(elon, elat, edepth)
end

function Base.show(io::IO, g::OceanGrid)
    println("OceanGrid of size $(g.nlat)×$(g.nlon)×$(g.ndepth) (lat×lon×depth)")
end

"""
    OceanGridBox

Ocean grid box.
Each grid can be looped over, where the `OceanGridBox` are the elements of the grid.
This useful to investigate specific boxes in the grid.
"""
struct OceanGridBox
    I
    lat          # °
    lon          # °
    depth        # m
    δlat         # °
    δlon         # °
    δdepth       # m
    δx           # m
    δy           # m
    δz           # m
    volume       # m³
    depth_top    # m
    A            # m²
end

"""
    box(g::OceanGrid, i, j, k)

Accesses the individual box of `g::OceanGrid` at index `(i,j,k)`.
Each grid can be looped over, where the `OceanGridBox` are the elements of the grid.
This useful to investigate specific boxes in the grid.
"""
function box(g::OceanGrid, i, j, k)
    return OceanGridBox(
                        CartesianIndex(i,j,k),
                        g.lat[i],
                        g.lon[j],
                        g.depth[k],
                        g.δlat[i],
                        g.δlon[j],
                        g.δdepth[k],
                        g.δx_3D[i,j,k],
                        g.δy_3D[i,j,k],
                        g.δz_3D[i,j,k],
                        g.volume_3D[i,j,k],
                        g.depth_top[k],
                        g.A_2D[i,j]
                       )
end

"""
    box(g::OceanGrid, I)

Accesses the individual box of `g::OceanGrid` at index `I`.
Each grid can be looped over, where the `OceanGridBox` are the elements of the grid.
This useful to investigate specific boxes in the grid.
"""
function box(g::OceanGrid, I)
    i,j,k = CartesianIndices((g.nlat,g.nlon,g.ndepth))[I].I
    return box(g::OceanGrid, i, j, k)
end

"""
    Base.size(g::OceanGrid)

Size of the grid.
"""
Base.size(g::OceanGrid) = g.nlat, g.nlon, g.ndepth

function Base.show(io::IO, b::OceanGridBox)
    println("OceanGridBox at $(b.I):")
    println("  location: $(b.lat)N, $(b.lon)E")
    println("  depth: $(b.depth)")
    println("  size: $(b.δx |> u"km") × $(b.δy |> u"km") × $(b.δz) (δx × δy × δz)")
end

area(b::OceanGridBox) = b.A |> u"km^2"
volume(b::OceanGridBox) = b.volume

Base.iterate(g::OceanGrid) = box(g::OceanGrid, 1), 1
function Base.iterate(g::OceanGrid, i)
    if i == g.nboxes
        return nothing
    else
        return box(g::OceanGrid, i+1), i+1
    end
end

export OceanGrid, OceanCurvilinearGrid, OceanRectilinearGrid, box, OceanGridBox

end # module
