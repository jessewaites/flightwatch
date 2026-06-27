# Pagy configuration. The anomalies feed paginates a plain Ruby Array (the file-bus snapshot),
# so we need the array extra. Default to 10 items (the most-recent page).
require "pagy/extras/array"

Pagy::DEFAULT[:items] = 10
