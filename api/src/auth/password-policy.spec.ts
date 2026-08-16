import { SEED_PASSWORD } from '../../prisma/seed-data';
import { generateProvisionalPassword } from './password.util';
import { MIN_PASSWORD_LENGTH, passwordProblem } from './password-policy';

/**
 * A REGRA DE SENHA.
 *
 * Estes testes existem porque a regra é fácil de afrouxar sem perceber: ela
 * mora em um arquivo só, é usada por três caminhos (cadastro, troca da própria
 * senha e o script de emergência do servidor) e nenhum deles reclama se ela
 * ficar permissiva demais — só um teste reclama.
 */
describe('política de senha', () => {
  const aceita = (password: string, owner = {}) => passwordProblem(password, owner) === null;

  describe('comprimento', () => {
    it('recusa o que for mais curto que o piso', () => {
      expect(passwordProblem('curta12')).toContain(`${MIN_PASSWORD_LENGTH} caracteres`);
    });

    it('aceita a partir do piso', () => {
      expect(aceita('cavalo-roxo')).toBe(true);
    });

    /**
     * Comprimento sem variedade não é força: `ababababab` tem dez caracteres e
     * a resistência de dois. Foi um teste desta suíte que encontrou a falta
     * desta regra — a versão anterior só olhava repetição de UM caractere.
     */
    it('recusa o comprimento feito de repetição', () => {
      expect(aceita('t'.repeat(MIN_PASSWORD_LENGTH - 1) + 'x')).toBe(false);
      expect(passwordProblem('ababababab')).toContain('caracteres diferentes');
    });

    /**
     * O teto não é preciosismo: o scrypt gasta o mesmo tempo para uma senha de
     * 10 KB e para dez mil senhas normais. Sem limite, o campo de senha vira
     * porta de exaustão do servidor.
     */
    it('recusa a senha absurdamente longa', () => {
      expect(passwordProblem('a-frase-longa-'.repeat(100))).toContain('não pode passar');
    });
  });

  describe('senhas conhecidas', () => {
    it.each(['123456789010', 'password123', 'senha1234', 'agrobarter2026', 'qwertyuiop'])(
      'recusa %s',
      (password) => {
        expect(aceita(password)).toBe(false);
      },
    );

    /** A lista casa sem acento e sem caixa: `Senha1234` é a mesma tentativa. */
    it('não escapa trocando a caixa nem pondo acento', () => {
      expect(aceita('SENHA1234')).toBe(false);
      expect(aceita('sênha1234')).toBe(false);
    });
  });

  describe('sequências', () => {
    /**
     * `0987654321` é o caso que a primeira versão desta regra deixava passar:
     * ela conferia se o passo entre as letras era sempre +1, e o pulo do `0`
     * para o `9` quebra a conta logo na primeira. Quem escolhe essa senha não
     * está fazendo aritmética — está descendo a fileira de números.
     */
    it.each(['aaaaaaaaaa', '1234567890', '0987654321', 'abcdefghij', 'qwertyuiop', 'poiuytrewq'])(
      'recusa %s',
      (password) => {
        expect(aceita(password)).toBe(false);
      },
    );

    /** Uma senha boa pode CONTER uma sequência — o que não pode é só ser uma. */
    it('não confunde com senha que apenas contém números em ordem', () => {
      expect(aceita('colheita-123-cerrado')).toBe(true);
    });
  });

  describe('contexto', () => {
    const joao = { email: 'joao.silva@agrobarter.com.br', fullName: 'João Silva' };

    it('recusa a senha que contém o nome de quem escolhe', () => {
      expect(passwordProblem('joaosilva-2026', joao)).toContain('seu nome');
    });

    it('recusa a senha que contém pedaço do e-mail', () => {
      expect(aceita('silva-do-campo', joao)).toBe(false);
    });

    it('recusa a senha que contém o nome do sistema', () => {
      expect(passwordProblem('agrobarter-forte-9')).toContain('nome do sistema');
    });

    /**
     * Palavras de até três letras ficam de fora da conferência de propósito:
     * `ana` dentro de `ana-lisa-do-campo` recusaria uma senha perfeitamente boa
     * de alguém chamado Ana — e a pessoa não teria como adivinhar o motivo.
     */
    it('não recusa por causa de pedaço curto do nome', () => {
      const ana = { email: 'ana.ferreira@agrobarter.com.br', fullName: 'Ana Ferreira' };
      expect(aceita('ana-lisa-do-campo', ana)).toBe(true);
    });

    it('sem contexto, só as regras que não dependem dele valem', () => {
      expect(aceita('joaosilva-2026')).toBe(true);
    });
  });

  it('aceita a frase longa e comum, que é o que se quer incentivar', () => {
    expect(aceita('meu boi fugiu na terça')).toBe(true);
  });

  /**
   * A INVARIANTE QUE FECHA O CÍRCULO: o sistema não pode CRIAR uma senha que
   * ele próprio RECUSARIA.
   *
   * Já criou, das duas formas. A senha provisória saía com 9 caracteres quando
   * o piso já era 10, e o dataset de demonstração nascia com `123456` — que é,
   * literalmente, o primeiro item da lista de senhas proibidas logo acima.
   * Nenhum dos dois quebrava nada de imediato, e é por isso que sobreviveram:
   * o gerador não consulta a política, então só um teste como este liga as
   * duas pontas.
   */
  describe('as senhas que o próprio sistema gera passam na política', () => {
    /**
     * Cem sorteios, não um. A provisória é aleatória, e um único sorteio
     * testaria a sorte daquela execução em vez da regra — uma combinação
     * pobre demais em caracteres distintos passaria despercebida por meses.
     */
    it('a senha provisória sorteada, em cem sorteios seguidos', () => {
      for (let attempt = 0; attempt < 100; attempt++) {
        const provisional = generateProvisionalPassword();
        expect(passwordProblem(provisional)).toBeNull();
      }
    });

    it('a senha do dataset de demonstração', () => {
      expect(passwordProblem(SEED_PASSWORD)).toBeNull();
    });
  });
});
