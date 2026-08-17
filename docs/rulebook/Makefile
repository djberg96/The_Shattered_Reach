PDF=build/the-shattered-reach-rulebook.pdf
PUBLISHED=../../public/the-shattered-reach-rulebook.pdf
CHAPTERS=$(wildcard chapters/*.tex)

all: $(PUBLISHED)

$(PUBLISHED): $(PDF)
	cp $(PDF) $(PUBLISHED)

$(PDF): main.tex $(CHAPTERS)
	@mkdir -p build
	latexmk -xelatex -interaction=nonstopmode -halt-on-error -outdir=build main.tex
	@mv build/main.pdf $(PDF)

clean:
	latexmk -C -outdir=build
