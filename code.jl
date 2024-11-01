using Pkg

Pkg.activate(@__DIR__)
Pkg.instantiate()

using HTTP, Gumbo, Cascadia
using WebDriver, DefaultApplication
using DataFrames, CSV
using ProgressBars
using Plots, StatsPlots
using StatsBase

# inititate chrome
DefaultApplication.open("chromedriver") 
capabilities = Capabilities("chrome")

wd = RemoteWebDriver(
  capabilities,
  host = "localhost",
  port = 65094
)
session = Session(wd)

function get_athlete_names(sport, session, sleep_time=1)
  url = "https://olympics.com/en/paris-2024/athletes/" * sport
  navigate!(session, url)
  sleep(sleep_time)

  cookies_button = Element(session, "css selector", "#onetrust-accept-btn-handler")
  try 
    click!(cookies_button)
  catch
  end
  println("Webpage Loaded")

  athlete_names = Vector{String}()
  box = Element(session, "css selector", "div.mirs-pagination-right")
  sleep(sleep_time)
  for _ ∈ 1:3
    moveto!(box)
    sleep(sleep_time)
  end
  while true
    html = parsehtml(source(session))
    matches = eachmatch(Selector("span.competitor-long-name"), html.root[2])
  
    for item ∈ matches
        push!(athlete_names, nodeText(item))
    end

    next_button = Element(session, "css selector", "div.mirs-pagination-right > button:nth-child(2)")
    if isenabled(next_button)
      click!(next_button)
      sleep(sleep_time)
    else 
      break 
    end
  end
  
  unique!(athlete_names)
end


sports = ["artistic-gymnastics", "football", "swimming", "volleyball", "basketball", "athletics"]

n_athletes = Vector{Int}()
athlete_name = Vector{String}()
for s ∈ sports
  out = get_athlete_names(s, session)
  append!(athlete_name, out)
  push!(n_athletes, length(out))
end

df = DataFrame(athlete_name=athlete_name,
  sport = reduce(vcat, fill.(sports, n_athletes)),
  wiki_name = "",
  month = 0
)

# strip trailing white space
df[:,:athlete_name] = strip.(df[:,:athlete_name])

for i ∈ 1:nrow(df)
  split_name = split(df[i,:athlete_name], r"(\s)(?=[A-Z][a-z]+)"; limit=2)
  if length(split_name) == 2
    df[i,:wiki_name] = replace(split_name[2] * "_" * titlecase(split_name[1]), " " => "_")
  else
    df[i,:wiki_name] = titlecase(split_name[1])
  end
end

# CSV.write("athlete_df.csv", df)
# df = CSV.read("athlete_df.csv", DataFrame)

function get_athlete_birth_month!(df)
  n = size(df,1)
  for i ∈ ProgressBar(1:n)
    url = "https://en.wikipedia.org/wiki/" * df[i,:wiki_name]
    try 
      html = HTTP.get(url)
      parsed = parsehtml(String(html))
      date_string = eachmatch(Selector("span.bday"), parsed.root)[1] |>
        nodeText
      df[i,:month] = parse(Int64, match(r"(?<=-)[0-9]{2}(?=-)", date_string).match)
    catch
    end
  end
end

get_athlete_birth_month!(df)

# CSV.write("athlete_df.csv", df)
# df = CSV.read("athlete_df.csv", DataFrame)

# Analysis Portion
df[:,:sport_type] = ifelse.(df.sport .∈ (["football", "volleyball", "basketball"],), "team", "individual")
filter!(:month => !=(0), df)

ind = combine(groupby(df[df.sport_type .== "individual",:], :month), nrow => :count)
team = combine(groupby(df[df.sport_type .== "team",:], :month), nrow => :count)

ind.rel_freq = ind.count ./ sum(ind.count)
team.rel_freq = team.count ./ sum(team.count)

both = innerjoin(ind, team, on=:month, makeunique=true)
select!(both,[:month, :rel_freq, :rel_freq_1])
rename!(both, ["Month", "Individual", "Team"])

pretty_table(both, backend=Val(:markdown), formatters=ft_printf("%5.3f", [2,3]))

p1 = bar(ind.month, ind.rel_freq, yaxis="Relative Frequency", legend=false, title="Individual")
p2 = bar(team.month, team.rel_freq, legend=false, title="Team")
p = plot(p1,p2, xaxis="Month", layout=(1,2))

savefig(p, "figures/fig1")