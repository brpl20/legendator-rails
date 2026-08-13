class PagesController < ApplicationController
  def home
  end

  def politica_de_privacidade
  end

  # Nao havia sitemap: o crawler so achava o que estivesse linkado a partir
  # da home. Sao poucas rotas publicas e todas estaticas, entao a lista e
  # explicita - as paginas de traducao tem id por pedido e ficam de fora
  # de proposito.
  def sitemap
    @entries = [
      { loc: root_url,                     changefreq: "weekly",  priority: "1.0" },
      { loc: new_translation_url,          changefreq: "monthly", priority: "0.8" },
      { loc: recover_url,                  changefreq: "monthly", priority: "0.5" },
      { loc: politica_de_privacidade_url,  changefreq: "yearly",  priority: "0.3" }
    ]

    render layout: false, formats: [ :xml ]
  end
end
