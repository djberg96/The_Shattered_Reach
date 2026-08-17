PDF=build/the-shattered-reach-ship-cards.pdf
PUBLIC_PDF=../../public/the-shattered-reach-ship-cards.pdf
GAME_DATA=../../app/services/shattered_reach/game_definition.rb
SHIP_ART=$(wildcard ../../app/assets/images/ships/tactical/*.png)

.PHONY: all clean

all: $(PDF) $(PUBLIC_PDF)

build/cards.tex: generate.rb $(GAME_DATA)
	@mkdir -p build
	ruby generate.rb > $@

$(PDF): main.tex build/cards.tex $(SHIP_ART)
	latexmk -xelatex -interaction=nonstopmode -halt-on-error -outdir=build main.tex
	@mv build/main.pdf $(PDF)

$(PUBLIC_PDF): $(PDF)
	cp $(PDF) $(PUBLIC_PDF)

clean:
	latexmk -C -outdir=build main.tex
	rm -f build/cards.tex $(PDF) $(PUBLIC_PDF)
