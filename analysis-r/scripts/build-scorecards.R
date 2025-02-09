library(tidyverse)
library(gt)

# plan scores
demographics <- read_csv("analysis-r/tables/plan-demographics.csv")
contiguity <- read_csv("analysis-r/tables/plan-contiguity.csv")
splits <- read_csv("analysis-r/tables/plan-muni-and-county-splits.csv")
compactness <- read_csv("analysis-r/tables/plan-aggregate-compactness.csv")
partisanship <- read_csv("analysis-r/tables/plan-vote-margins.csv")

################################################################################
# prepare for table merging
demographics.2 <- demographics |>
  select(plan, total_pop_deviation = pct_deviation, black, hispanic, none)

contiguity.2 <- contiguity |>
  # Change legis24_wsa == 41 to contiguous because some islands are separated by water
  #   instead of leaving the water block (550471004003059) unassigned,
  #   this plan assigns it to district 42. However, a literal island still counts
  #   as contiguous, per SCOWIS ruling
  filter(! (plan == "legis24_wsa" & dist_number == 41 & components > 1)) |>
  group_by(plan) |>
  summarise(noncontiguous_districts = sum(contiguous == "noncontiguous")) |>
  mutate(contiguity = if_else(noncontiguous_districts == 0,
                              "Yes",
                              paste0("No (", noncontiguous_districts, " splits)"))) |>
  select(plan, contiguity) |>
  # Joint Stipulation states that the discontiguous census blocks in the
  #   Senate Democrats plan shouldn't be counted as discontiguous
  mutate(contiguity = if_else(str_detect(plan, "sendems"), "Yes", contiguity))

splits.2 <- splits

compactness.2 <- compactness |>
  select(plan, reock)

partisanship.2 <- partisanship |>
  filter(district != "ZZZ") |>
  group_by(plan) |>
  mutate(rep = sum(modelled_outcome_22 < 0),
         dem = sum(modelled_outcome_22 > 0)) |>
  arrange(modelled_outcome_22) |>
  filter((word(plan, -1, sep = "_") == "wsa" & row_number() == 50) |
           (word(plan, -1, sep = "_") == "wss" & row_number() == 17)) |>
  ungroup() |>
  select(plan, rep, dem, median_seat_lean = modelled_outcome_22)

################################################################################
# create table

combine <- demographics.2 |>
  inner_join(contiguity.2) |>
  inner_join(splits.2) |>
  inner_join(compactness.2) |>
  inner_join(partisanship.2) |>
  separate(plan, into = c("plan", "house"), sep = "_") |>
  mutate(
    era = if_else(plan %in% c("legis","pmc","everslc"), "old submissions (2022)", "new submissions (2024)"),
    plan = case_when(
      plan == "legis" ~ "GOP Legislature 2021",
      plan == "pmc" ~ "People's Map Commission 2021",
      plan == "everslc" ~ "Evers' Least Change 2021",
      plan == "legis24" ~ "Legislative Republicans",
      plan == "evers24" ~ "Evers 2024",
      plan == "wright" ~ "Wright Petitioners",
      plan == "sendems" ~ "Senate Democrats",
      plan == "petering" ~ "Petering (FastMap)",
      plan == "will" ~ "W.I.L.L.",
      plan == "lawforward" ~ "Law Forward",
      TRUE ~ plan),
    house = if_else(house == "wss", "Senate", "Assembly"))

assembly.gt <- combine |>
  filter(house == "Assembly") |>
  select(-house) |>
  group_by(era) |>
  gt(rowname_col = "plan") |>
  row_group_order(c("new submissions (2024)", "old submissions (2022)")) |>
  tab_spanner(label = "Majority Minority Districts", columns = c(black, hispanic, none)) |>
  tab_spanner(label = "# split by districts", columns = starts_with("split")) |>
  tab_spanner(label = "2022 outcome", columns = c(dem, rep)) |>
  cols_label(
    total_pop_deviation = "Pop. deviation",
    black = "Black",
    hispanic = "Hispanic",
    none = "No majority",
    contiguity = "Contiguous?",
    split_municipalities = "municipalities",
    split_counties = "counties",
    split_wards = "wards",
    reock = "Avg. compactness",
    dem = "Dem.",
    rep = "Rep.",
    median_seat_lean = "Tipping point seat"
  ) |>
  cols_width(
    plan ~ px(250),
    total_pop_deviation ~ px(90),
    black ~ px(50),
    hispanic ~ px(75),
    none ~ px(100),
    contiguity ~ px(110),
    split_municipalities ~ px(110),
    split_counties ~ px(90),
    split_wards ~ px(60),
    reock ~ px(110),
    dem ~ px(60),
    rep ~ px(60),
    median_seat_lean ~ px(100)
  ) |>
  fmt_percent(columns = total_pop_deviation, decimals = 2, scale_values = F) |>
  fmt_number(columns = reock, decimals = 2) |>
  tab_header("Wisconsin Assembly Redistricting Plan Scorecard",
             subtitle = md(("using criteria outlined by the Wisconsin Supreme Court in *Rebecca Clarke v. Wisconsin Elections Commission*"))) |>
  tab_stubhead("plan submitted by") |>
  tab_style(style = cell_text(style = "italic"),
            locations = cells_stubhead()) |>
  tab_style(style = cell_text(font = "italic", weight = "bold"),
            locations = cells_row_groups()) |>
  tab_style(style = cell_text(weight = "bold", size = 16),
            locations = cells_title()) |>
  data_color(columns = total_pop_deviation, palette = "Oranges", domain = c(0,5)) |>
  data_color(columns = c(black, hispanic, none), palette = "Oranges", domain = c(0,8)) |>
  tab_style(style = cell_fill(color = "red"),
            locations = cells_body(columns = contiguity, rows = contiguity != "Yes")) |>
  tab_style(style = cell_text(weight = "bold"),
            locations = cells_body(columns = contiguity, rows = contiguity == "Yes")) |>
  data_color(columns = split_municipalities, palette = "Oranges", domain = c(0, 260)) |>
  data_color(columns = split_counties, palette = "Oranges", domain = c(0, 72)) |>
  data_color(columns = split_wards, palette = "Oranges", domain = c(0, 260)) |>
  data_color(columns = reock, palette = "Oranges", domain = c(0.3, 0.45)) |>
  data_color(columns = dem, palette = "Blues", domain = c(35, 65)) |>
  data_color(columns = rep, palette = "Reds", domain = c(35, 65), reverse = T) |>
  data_color(columns = median_seat_lean, palette = "Reds", domain = c(-17, 0),
             rows = median_seat_lean < 0, reverse = T) |>
  # data_color(columns = median_seat_lean, palette = "Blues", domain = c(0, 17),
  #            rows = median_seat_lean > 0) |>
  fmt(columns = median_seat_lean,
      rows = median_seat_lean < 0,
      fns = function(x){paste0("+", round(abs(x), 1), " Rep")}) |>
  fmt(columns = median_seat_lean,
      rows = median_seat_lean > 0,
      fns = function(x){paste0("+", round(abs(x), 1), " Dem")}) |>
  fmt(columns = median_seat_lean,
      rows = median_seat_lean == 0,
      fns = function(x){paste0("tie")}) |>
  tab_footnote(footnote = "Population deviation is the range between the most populous and least population districts, divided by the ideal district size.",
               locations = cells_column_labels("total_pop_deviation")) |>
  tab_footnote(footnote = "Number of districts where each group forms a majority of adults.",
               locations = cells_column_spanners("Majority Minority Districts")) |>
  tab_footnote(footnote = "Only includes adults choosing non-Hispanic Black alone",
               local(cells_column_labels("black"))) |>
  tab_footnote(footnote = "Number of each split into multiple districts that themselves cross muni/county lines.",
               locations = cells_column_spanners("# split by districts")) |>
  tab_footnote(footnote = "Average Reock score for the plan. A district's Reock score is ratio of the district's area to the area of the smallest circle that can be drawn around the district.",
               locations = cells_column_labels("reock")) |>
  tab_footnote(footnote = "The modelled outcome of the 2022 legislative election in this district, modelled using results from statewide races.",
               locations = cells_column_spanners("2022 outcome")) |>
  tab_footnote(footnote = "The modelled lean of the 50th seat in the 2022 Assembly elections, modelled using results from statewide races.",
               locations = cells_column_labels("median_seat_lean")) |>
  tab_footnote(footnote = "The Senate Democrats plan includes 7 districts with disconnected portions, according to the US Census Bureau Census Block GIS file. However, the parties agreed in a joint stipulation dated 1/2/2024 to nonetheless count these as contiguous.",
               locations = cells_body(columns = "contiguity", rows = plan == "Senate Democrats")) |>
  tab_footnote(footnote = "This does not include any ward splits which the parties agreed not to count as such in a joint stipulation dated 1/2/2024.",
               locations = cells_column_labels(columns = "split_wards")) |>
  tab_footnote(footnote = "On January 17, the Court ruled that the would not consider the Petering submission, as Petering was not among the original petitioners in the case.",
               locations = cells_stub(plan == "Petering (FastMap)")) |>
  tab_footnote(footnote = "The final wards were drawn to match the boundaries of this plan.",
               locations = cells_body(columns = split_wards, rows = plan == "GOP Legislature 2021")) |>
  tab_source_note(md("Analysis by John D. Johnson, Marquette Law School Lubar Center Research Fellow. See [github.com/jdjohn215/wi-legis-map-proposals-2024](https://github.com/jdjohn215/wi-legis-map-proposals-2024/tree/main) for all methodological details, data, and code."))
assembly.gt

senate.gt <- combine |>
  filter(house == "Senate") |>
  select(-house) |>
  group_by(era) |>
  gt(rowname_col = "plan") |>
  row_group_order(c("new submissions (2024)", "old submissions (2022)")) |>
  tab_spanner(label = "Majority Minority Districts", columns = c(black, hispanic, none)) |>
  tab_spanner(label = "# split by districts", columns = starts_with("split")) |>
  tab_spanner(label = "2022 outcome", columns = c(dem, rep)) |>
  cols_label(
    total_pop_deviation = "Pop. deviation",
    black = "Black",
    hispanic = "Hispanic",
    none = "No majority",
    contiguity = "Contiguous?",
    split_municipalities = "municipalities",
    split_counties = "counties",
    split_wards = "wards",
    reock = "Avg. compactness",
    dem = "Dem.",
    rep = "Rep.",
    median_seat_lean = "Tipping point seat"
  ) |>
  cols_width(
    plan ~ px(250),
    total_pop_deviation ~ px(90),
    black ~ px(50),
    hispanic ~ px(75),
    none ~ px(100),
    contiguity ~ px(110),
    split_municipalities ~ px(110),
    split_counties ~ px(90),
    split_wards ~ px(60),
    reock ~ px(110),
    dem ~ px(60),
    rep ~ px(60),
    median_seat_lean ~ px(100)
  ) |>
  fmt_percent(columns = total_pop_deviation, decimals = 2, scale_values = F) |>
  fmt_number(columns = reock, decimals = 2) |>
  tab_header("Wisconsin State Senate Redistricting Plan Scorecard",
             subtitle = md(("using criteria outlined by the Wisconsin Supreme Court in *Rebecca Clarke v. Wisconsin Elections Commission*"))) |>
  tab_stubhead("plan submitted by") |>
  tab_style(style = cell_text(style = "italic"),
            locations = cells_stubhead()) |>
  tab_style(style = cell_text(font = "italic", weight = "bold"),
            locations = cells_row_groups()) |>
  tab_style(style = cell_text(weight = "bold", size = 16),
            locations = cells_title()) |>
  data_color(columns = total_pop_deviation, palette = "Oranges", domain = c(0,2)) |>
  data_color(columns = c(black, hispanic, none), palette = "Oranges", domain = c(0,6)) |>
  tab_style(style = cell_fill(color = "red"),
            locations = cells_body(columns = 6, rows = contiguity != "Yes")) |>
  tab_style(style = cell_text(weight = "bold"),
            locations = cells_body(columns = 6, rows = contiguity == "Yes")) |>
  data_color(columns = split_municipalities, palette = "Oranges", domain = c(0, 260)) |>
  data_color(columns = split_counties, palette = "Oranges", domain = c(0, 72)) |>
  data_color(columns = split_wards, palette = "Oranges", domain = c(0, 260)) |>
  data_color(columns = reock, palette = "Oranges", domain = c(0.3, 0.4)) |>
  data_color(columns = dem, palette = "Blues", domain = c(10, 24)) |>
  data_color(columns = rep, palette = "Reds", domain = c(10, 24), reverse = T) |>
  data_color(columns = median_seat_lean, palette = "Blues", domain = c(0, 17),
             rows = median_seat_lean > 0) |>
  data_color(columns = median_seat_lean, palette = "Reds", domain = c(-17, 0),
             rows = median_seat_lean < 0, reverse = T) |>
  fmt(columns = median_seat_lean,
      rows = median_seat_lean < 0,
      fns = function(x){paste0("+", round(abs(x), 1), " Rep")}) |>
  fmt(columns = median_seat_lean,
      rows = median_seat_lean > 0,
      fns = function(x){paste0("+", round(abs(x), 1), " Dem")}) |>
  fmt(columns = median_seat_lean,
      rows = median_seat_lean == 0,
      fns = function(x){paste0("tie")}) |>
  tab_footnote(footnote = "Population deviation is the range between the most populous and least population districts, divided by the ideal district size.",
               locations = cells_column_labels("total_pop_deviation")) |>
  tab_footnote(footnote = "Number of districts where each group forms a majority of adults.",
               locations = cells_column_spanners("Majority Minority Districts")) |>
  tab_footnote(footnote = "Only includes adults choosing non-Hispanic Black alone",
               local(cells_column_labels("black"))) |>
  tab_footnote(footnote = "Number of each split into multiple districts that themselves cross muni/county lines.",
               locations = cells_column_spanners("# split by districts")) |>
  tab_footnote(footnote = "Average Reock score for the plan. A district's Reock score is ratio of the district's area to the area of the smallest circle that can be drawn around the district.",
               locations = cells_column_labels("reock")) |>
  tab_footnote(footnote = "The modelled outcome of the 2022 legislative election in this district, modelled using results from statewide races.",
               locations = cells_column_spanners("2022 outcome")) |>
  tab_footnote(footnote = "The modelled lean of the 17th seat in the 2022 State Senate elections (had all seats been contested), modelled using results from statewide races. In reality, only even or odd-numbered seats are up for reelection at a time.",
               locations = cells_column_labels("median_seat_lean")) |>
  tab_footnote(footnote = "The Senate Democrats plan includes 2 districts with disconnected portions, according to the US Census Bureau Census Block GIS file. However, the parties agreed in a joint stipulation dated 1/2/2024 to nonetheless count these as contiguous.",
               locations = cells_body(columns = "contiguity", rows = plan == "Senate Democrats")) |>
  tab_footnote(footnote = "On January 17, the Court ruled that the would not consider the Petering submission, as Petering was not among the original petitioners in the case.",
               locations = cells_stub(plan == "Petering (FastMap)")) |>
  tab_footnote(footnote = "This does not include any ward splits which the parties agreed not to count as such in a joint stipulation dated 1/2/2024.",
               locations = cells_column_labels(columns = "split_wards")) |>
  tab_footnote(footnote = "The final wards were drawn to match the boundaries of this plan.",
               locations = cells_body(columns = split_wards, rows = plan == "GOP Legislature 2021")) |>
  tab_source_note(md("Analysis by John D. Johnson, Marquette Law School Lubar Center Research Fellow. See [github.com/jdjohn215/wi-legis-map-proposals-2024](https://github.com/jdjohn215/wi-legis-map-proposals-2024/tree/main) for all methodological details, data, and code."))
senate.gt

################################################################################
# save output
gtsave(assembly.gt, "scorecards/assembly-scorecard.png", vwidth = 1350)
gtsave(assembly.gt, "scorecards/assembly-scorecard.html")
gtsave(senate.gt, "scorecards/senate-scorecard.png", vwidth = 1350)
gtsave(senate.gt, "scorecards/senate-scorecard.html")


################################################################################
# compactness scores
compactness |>
  select(-total_perimeter) |>
  pivot_longer(cols = -c(house, plan)) |>
  mutate(plan = word(plan, 1, sep = "_")) |>
  pivot_wider(names_from = c(house, plan), values_from = value) |>
  gt(rowname_col = "name") |>
  tab_spanner_delim("_") |>
  fmt_number(columns = where(is.numeric), decimals = 2)
