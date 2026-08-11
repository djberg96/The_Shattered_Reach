PDF=build/the-shattered-reach-rulebook.pdf

all: $(PDF)

$(PDF): main.tex
	@mkdir -p build
	latexmk -xelatex -interaction=nonstopmode -halt-on-error -outdir=build main.tex
	@mv build/main.pdf $(PDF)

clean:
	latexmk -C -outdir=build
