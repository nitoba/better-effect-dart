import Link from 'next/link';
import Image from 'next/image';
import { ArrowUpRight } from 'lucide-react';

const principles = [
  {
    title: 'Falhas que têm tipo',
    description:
      'Effects descrevem operações assíncronas com sucesso, falha esperada e defeito inesperado sem misturar os três caminhos.',
  },
  {
    title: 'Dependências explícitas',
    description:
      'Modules tornam o grafo de serviços visível e permitem compor implementações sem esconder o composition root.',
  },
  {
    title: 'Recursos com fim',
    description:
      'Runtime e Scope definem quem cria, usa e fecha recursos, do trabalho local à vida inteira da aplicação.',
  },
];

export default function HomePage() {
  return (
    <main className="be-home">
      <section className="be-hero">
        <div className="be-hero-content">
          <div className="be-hero-copy">
            <div className="be-hero-meta">
              <Image src="/logo.png" alt="" width={40} height={40} priority style={{ filter: 'none' }} />
              <span>better_effect</span>
              <span className="be-meta-divider" aria-hidden="true" />
              <span>Dart + Flutter</span>
            </div>
            <h1>
              <span>Faça o fluxo</span>
              <span>da sua app <em>óbvio.</em></span>
            </h1>
            <p className="be-hero-description">
              Uma arquitetura Dart e Flutter pequena para compor dependências,
              proteger fronteiras de erro e fechar o que foi aberto.
            </p>
            <div className="be-hero-actions">
              <Link href="/docs/getting-started" className="be-button be-button-primary">
                Começar agora <ArrowUpRight aria-hidden="true" />
              </Link>
              <Link href="/docs" className="be-text-link be-hero-docs-link">
                Ler a documentação <span aria-hidden="true">→</span>
              </Link>
            </div>
          </div>

          <div className="be-hero-art" aria-label="Exemplo de composição better_effect">
            <div className="be-art-heading">
              <div>
                <span className="be-art-overline">UM FLUXO EXPLÍCITO</span>
                <strong>Da fronteira ao runtime</strong>
              </div>
              <span className="be-art-status"><i /> ready</span>
            </div>

            <div className="be-architecture-rail" aria-label="Camadas da arquitetura">
              <div className="be-architecture-node"><span>01</span><strong>Effect</strong><small>descreve o trabalho</small></div>
              <div className="be-architecture-node"><span>02</span><strong>Module</strong><small>expõe dependências</small></div>
              <div className="be-architecture-node"><span>03</span><strong>Runtime</strong><small>executa e fecha</small></div>
            </div>

            <div className="be-terminal">
              <div className="be-terminal-bar">
                <span className="be-terminal-dots"><i /><i /><i /></span>
                <span>app.dart</span>
                <span className="be-terminal-state">better_effect / typed</span>
              </div>
              <div className="be-terminal-body">
                <div className="be-line"><span className="be-ln">01</span><span><b className="be-keyword">import</b> <b className="be-string">&apos;package:better_effect/better_effect.dart&apos;</b>;</span></div>
                <div className="be-line"><span className="be-ln">02</span><span /></div>
                <div className="be-line"><span className="be-ln">03</span><span><b className="be-keyword">final</b> module = <b className="be-class">Module</b>([</span></div>
                <div className="be-line"><span className="be-ln">04</span><span>  <b className="be-class">Binding</b>.singleton&lt;<b className="be-type">Api</b>&gt;(<b className="be-type">Api</b>.new),</span></div>
                <div className="be-line"><span className="be-ln">05</span><span>]);</span></div>
                <div className="be-line"><span className="be-ln">06</span><span /></div>
                <div className="be-line"><span className="be-ln">07</span><span><b className="be-keyword">final</b> program = <b className="be-class">Effect</b>.result((use) async =&gt; &#123;</span></div>
                <div className="be-line"><span className="be-ln">08</span><span>  <b className="be-keyword">final</b> api = use&lt;<b className="be-type">Api</b>&gt;();</span></div>
                <div className="be-line"><span className="be-ln">09</span><span>  <b className="be-keyword">return</b> api.fetch();</span></div>
                <div className="be-line"><span className="be-ln">10</span><span>&#125;);</span></div>
                <div className="be-line"><span className="be-ln">11</span><span /></div>
                <div className="be-line"><span className="be-ln">12</span><span><b className="be-keyword">await</b> runtime.run(program);</span></div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section className="be-intro-section">
        <div className="be-intro-grid">
          <h2>Fique com as partes boas do Effect. Mantenha sua aplicação sua.</h2>
          <div>
            <p>
              better_effect fica próximo de Dart, Future e ResultDart. Não há
              scheduler oculto nem um container que o domínio precise aprender.
            </p>
            <Link href="/docs/getting-started/mental-model" className="be-text-link">
              Entender o modelo mental <ArrowUpRight aria-hidden="true" />
            </Link>
          </div>
        </div>
      </section>

      <section className="be-principles-section">
        <div className="be-section-heading">
          <h2>Três decisões para um fluxo que continua explicável.</h2>
          <p>Pequenas fronteiras, composáveis desde o primeiro serviço até a aplicação inteira.</p>
        </div>
        <div className="be-principles-list">
          {principles.map((principle) => (
            <article className="be-principle" key={principle.title}>
              <h3>{principle.title}</h3>
              <p>{principle.description}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="be-cta-section">
        <div className="be-cta-image" aria-label="Fluxo de execução better_effect">
          <div className="be-cta-visual-heading">
            <span>COMPOSITION ROOT</span>
            <span>runtime / closed</span>
          </div>
          <div className="be-cta-flow">
            <div><strong>Effect</strong><span>descreve</span></div>
            <i aria-hidden="true">→</i>
            <div><strong>Module</strong><span>compõe</span></div>
            <i aria-hidden="true">→</i>
            <div><strong>Runtime</strong><span>fecha</span></div>
          </div>
          <code>await runtime.run(program);</code>
        </div>
        <div className="be-cta-copy">
          <h2>Comece com um serviço.<br /><em>Cresça com confiança.</em></h2>
          <p>Leia o guia, monte seu primeiro Module e deixe o analyzer mostrar o que sua aplicação precisa.</p>
          <Link href="/docs/getting-started" className="be-button be-button-primary">
            Abrir o guia <ArrowUpRight aria-hidden="true" />
          </Link>
        </div>
      </section>

      <footer className="be-home-footer">
        <div className="be-footer-brand"><Image src="/logo.png" alt="" width={28} height={28} style={{ filter: 'none' }} /> <span>better_effect</span></div>
        <span>Arquitetura tipada para Dart e Flutter.</span>
        <Link href="/docs">Documentação <ArrowUpRight aria-hidden="true" /></Link>
      </footer>
    </main>
  );
}
