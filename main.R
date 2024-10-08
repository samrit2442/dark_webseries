pacman::p_load(tidyverse, RSQLite, DBI, vroom, here, colorspace, 
               ggfx, ggtext, ragg, shadowtext, extrafont, showtext, sysfonts,
               systemfonts)

base_path <- here()

con <- dbConnect(SQLite(), here(base_path, "data/imdb.db"))
dbListTables(con)

title_basics <- vroom(here(base_path, "data/imdb_input", "title.basics.tsv.gz"))
title_episode <- vroom(here(base_path, "data/imdb_input", "title.episode.tsv.gz"))
title_ratings <- vroom(here(base_path, "data/imdb_input", "title.ratings.tsv.gz"))

dbDisconnect(con)

basics_st <- title_basics |>  
  filter(primaryTitle == "Dark", 
         titleType == "tvSeries")

parent_title_id <- basics_st |> 
  head(1) |> 
  pull(tconst)
parent_title_id

episodes_st <- title_episode |> 
  filter(parentTconst == parent_title_id) |> 
  inner_join(title_ratings, by = "tconst") |> 
  mutate(across(c(seasonNumber, episodeNumber), as.numeric)) |> 
  arrange(seasonNumber, episodeNumber) |> 
  collect()

annotate_richtext <- function(label, ...) {
  annotate("richtext", label = label,
           family = "rubik", size = 2.75,
           fill = NA, label.color = NA, color = "grey94", label.padding = unit(0.05, "mm"),
           hjust = 0,
           ...)
}

average_rating_season <- episodes_st  |> 
  group_by(seasonNumber)  |>  
  mutate(rating_votes = averageRating * numVotes) |> 
  summarise(wgt_avg_season_rating = sum(rating_votes) / sum(numVotes),
            avg_season_rating = mean(averageRating))
average_rating_season

episodes_st_cont <- episodes_st |> 
  arrange(seasonNumber, episodeNumber) |> 
  mutate(ep_cont = row_number())  |>  
  inner_join(average_rating_season, by = "seasonNumber")

episodes_st_cont_summary <- episodes_st_cont |> 
  group_by(seasonNumber) |> 
  summarize(ep_cont_min = min(ep_cont),
            ep_cont_median = median(ep_cont))

main_color <- "#0978e7"
bg_color <- "grey9"
title_pos <- 12.5
font_add_google("Roboto", "roboto")
font_add_google("Rubik", "rubik")
# font_add_google("Rubik", "Rubik Doodle Shadow")
# font_add_google("DM Sans", "sans-serif")
showtext_auto()


titles <- list(
  "title" = "D A R K",
  "subtitle" = "
  Dark is one of the best sci-fi series on Netflix. It has an overall rating of **8.7** on IMDB.
  There is variation between the ratings of the seasons and episodes, which is shown in this plot. 
  Each **dot** represents the average IMDB rating of an episode. The **horizontal** **bars** indicate 
  average season ratings (weighted by the number of votes).",
  "caption" = "Data: IMDB.com. Visualization: Samrit Pramanik")

ragg::agg_png(here(base_path, "plots/dark_episode_ratings.png"),
              width = 10, height = 6, res = 600, units = "in")
d <- episodes_st_cont |> 
  group_by(seasonNumber) |> 
  mutate(ep_cont_extended = case_when(
    ep_cont == min(ep_cont) ~ as.numeric(ep_cont) - 0.25,
    ep_cont == max(ep_cont) ~ as.numeric(ep_cont) + 0.25,
    TRUE ~ as.numeric(ep_cont)
  )) |> 
  ungroup() |> 
  ggplot(aes(ep_cont, averageRating, group = factor(seasonNumber))) +
  geom_curve(
    aes(xend = ep_cont, y = wgt_avg_season_rating, yend = averageRating),
    col = main_color,  lty = "solid",  linewidth = 0.8, curvature = 0.2) +
  with_shadow(
    geom_line(
      aes(ep_cont_extended, y = wgt_avg_season_rating),
      col = main_color, linewidth = 3, lty = "solid"),
    colour = "grey2", expand = 0.75, lineend = "butt", 
  ) +
  with_outer_glow(
    geom_point(color = "grey80", size = 3.5),
    expand = 15, colour = main_color, sigma = 21
  ) +
  # geom_point(color = "grey80", size = 3) + 
  geom_richtext(
    data = episodes_st_cont_summary,
    aes(
      x = ep_cont_median, y = 10.25,
      label = glue::glue(
        "<span style='font-size:15pt; color: grey72'>Season</span>
       <span style='font-size:30pt; color: #0978e7'>{seasonNumber}</span>"
      )
    ),
    stat = "unique", hjust = 0.5, vjust = 0.5, 
    family = "sans-serif", fill = NA, label.size = 0
  ) + 
  # annotate_richtext(
  #   label = "S2 E7 (\"The Lost Sister\")<br>is odd with a rating of 6.1",
  #   x = 9.5, y = 6) +
  shadowtext::geom_shadowtext(
    data = NULL,
    aes(x = nrow(episodes_st_cont) / 2, y = title_pos, label = titles$title),
    family = title_font, color = bg_color, bg.color = "#0978e7", size = 35,
    hjust = 0.5, vjust = 0.7, inherit.aes = FALSE, lineheight = 0.8) +
  # Custom subtitle
  annotate(GeomTextBox, x = nrow(episodes_st_cont) / 2, y = title_pos - 0.75, 
           label = titles$subtitle, color = "grey82", 
           width = 0.8, hjust = 0.5, halign = 0.5, vjust = 1, size = 7,
           lineheight = 1.25, family = "rubik", fill = NA, box.size = 0) + 
  scale_y_continuous(breaks = seq(7, 10, 1), minor_breaks = seq(7, 10, 0.5)) +
  coord_cartesian(ylim = c(7, title_pos), clip = "off") +
  guides(color = "none") +
  labs(caption = titles["caption"], y = "Average Rating") +
  theme_minimal(base_family = "rubik") +
  theme(
    plot.background = element_rect(color = NA, fill = bg_color),
    axis.title.x = element_blank(),
    axis.title.y = element_text(color = "grey62", size = 15),
    axis.text.x = element_blank(),
    axis.ticks.x = element_blank(),
    axis.text.y = element_text(color = "grey62", size = 17),
    panel.background = element_rect(color = NA, fill = NA),
    text = element_text(color = "grey82"),
    plot.caption = element_markdown(size = 18),
    panel.grid = element_blank(),
    panel.grid.major.y = element_line(color = "grey20", linewidth = 0.2),
    panel.grid.minor.y = element_line(color = "grey20", linewidth = 0.1)
  )

grid.draw(d)
# d
invisible(dev.off())

ggsave("./plots/high_quality_plot4.svg", 
       plot = grid.draw(d), width = 15, height = 7.5, dpi = 300, units = "in")




